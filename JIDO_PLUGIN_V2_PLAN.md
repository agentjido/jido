# Plugin System V2: Default Plugins Implementation Plan

## Goal

Evolve the plugin system to support **default plugins** — framework-provided singleton plugins that replace ad hoc reserved keys. This keeps the agent core minimal while proving that plugins are the universal composition mechanism.

The first two default plugins are `__strategy__` (state ownership only) and `__thread__`. Identity and Memory come later once the foundation is solid.

---

## Table of Contents

- [Phase A: Plugin System Foundation](#phase-a-plugin-system-foundation)
- [Phase B: Strategy State as Default Plugin](#phase-b-strategy-state-as-default-plugin)
- [Phase C: Thread as Default Plugin](#phase-c-thread-as-default-plugin)
- [Phase D: Plugin Checkpoint Hooks (Optional, Future)](#phase-d-plugin-checkpoint-hooks-optional-future)
- [Compile-Time vs Runtime Decision Map](#compile-time-vs-runtime-decision-map)
- [What NOT To Do](#what-not-to-do)
- [Migration and Breakage Analysis](#migration-and-breakage-analysis)

---

## Phase A: Plugin System Foundation

**Effort: M (3–5 hours)**
**Prerequisite for all subsequent phases.**

### A.1: Add `singleton` Option to Plugin Config Schema

**File: `lib/jido/plugin.ex`**

Add to `@plugin_config_schema`:

```elixir
singleton:
  Zoi.boolean(description: "If true, plugin cannot be aliased or duplicated.")
  |> Zoi.default(false)
```

Add generated accessor in `generate_pattern_accessors/0` (alongside `tags/0`, `capabilities/0`):

```elixir
@doc "Returns whether this plugin is a singleton."
@spec singleton?() :: boolean()
def singleton?, do: @validated_opts[:singleton] || false
```

Add to `defoverridable` list in `generate_defoverridable/0`:

```elixir
singleton?: 0
```

**File: `lib/jido/plugin/manifest.ex`**

Add field to manifest schema:

```elixir
singleton: Zoi.boolean(description: "Whether plugin is singleton") |> Zoi.default(false)
```

Update `manifest/0` generation in `plugin.ex` to include `singleton: singleton?()`.

**File: `lib/jido/plugin/instance.ex`**

Add runtime guardrail in `new/1`, after `normalize_declaration`:

```elixir
if module.singleton?() and as_opt != nil do
  raise ArgumentError,
    "Cannot alias singleton plugin #{inspect(module)} with `as: #{inspect(as_opt)}`"
end
```

This is a backstop — compile-time enforcement in the agent macro is the primary gate.

### A.2: Compile-Time Singleton Enforcement in Agent Macro

**File: `lib/jido/agent.ex`** (compile-time setup block, after `@plugin_instances` is built)

Add three validations after instance normalization:

```elixir
# 1. No aliasing singletons
singleton_alias_violations =
  @plugin_instances
  |> Enum.filter(fn inst -> inst.module.singleton?() and inst.as != nil end)

if singleton_alias_violations != [] do
  modules = Enum.map(singleton_alias_violations, & &1.module) |> Enum.map(&inspect/1)
  raise CompileError,
    description: "Cannot alias singleton plugins: #{Enum.join(modules, ", ")}",
    file: __ENV__.file,
    line: __ENV__.line
end

# 2. No duplicate singleton modules
singleton_modules =
  @plugin_instances
  |> Enum.filter(fn inst -> inst.module.singleton?() end)
  |> Enum.map(& &1.module)

duplicate_singletons = singleton_modules -- Enum.uniq(singleton_modules)

if duplicate_singletons != [] do
  raise CompileError,
    description: "Duplicate singleton plugins: #{inspect(Enum.uniq(duplicate_singletons))}",
    file: __ENV__.file,
    line: __ENV__.line
end
```

Note: the existing `@duplicate_keys` check already catches state_key collisions. Singleton validation is an additional semantic check.

### A.3: Default Plugin Auto-Inclusion

**File: `lib/jido/agent.ex`** (macro compile-time setup)

Replace the current plugin normalization with:

```elixir
# User-declared plugins
@user_plugin_decls @validated_opts[:plugins] || []

# Default plugins (framework-provided, mount last)
@default_plugin_decls Jido.Agent.__default_plugins__(@validated_opts)

# Final plugin list: user first, defaults last
@all_plugin_decls @user_plugin_decls ++ @default_plugin_decls

# Normalize to Instance structs
@plugin_instances Jido.Agent.__normalize_plugin_instances__(@all_plugin_decls)
```

**New function in `lib/jido/agent.ex`:**

```elixir
@doc false
def __default_plugins__(agent_opts) do
  defaults = []

  # Strategy state plugin (unless opted out)
  defaults =
    case agent_opts[:strategy_plugin] do
      false -> defaults
      nil -> defaults ++ [Jido.Agent.Strategy.StatePlugin]
      custom_module -> defaults ++ [custom_module]
    end

  # Thread plugin (unless opted out)
  defaults =
    case agent_opts[:thread_plugin] do
      false -> defaults
      nil -> defaults ++ [Jido.Thread.Plugin]
      custom_module -> defaults ++ [custom_module]
    end

  defaults
end
```

**Agent option for opting out:**

```elixir
# Disable thread default plugin
use Jido.Agent,
  name: "minimal",
  thread_plugin: false

# Swap strategy state plugin
use Jido.Agent,
  name: "custom",
  strategy_plugin: MyApp.CustomStrategyStatePlugin
```

**Mount ordering guarantee:** Default plugins mount after all user plugins. This is automatic because they're appended to the list, and `__mount_plugins__/1` iterates `@plugin_specs` in order.

### A.4: Pull-Based Contribution Callback

**File: `lib/jido/plugin.ex`**

Add optional callback to the behaviour:

```elixir
@doc """
Contribute data to a named topic during another plugin's mount.

Called by aggregator plugins (e.g., Identity) to pull contributions
from all mounted plugins. The topic atom identifies what's being
requested.

## Parameters

- `topic` - Atom identifying the contribution type (e.g., `:identity_extensions`)
- `config` - Per-agent configuration for this plugin

## Returns

- `map()` - Data to contribute (keyed by plugin name in the aggregator)
- `nil` - No contribution for this topic
"""
@callback contribute(topic :: atom(), config :: map()) :: map() | nil
```

Add default implementation in `generate_default_callbacks/0`:

```elixir
@doc false
@spec contribute(atom(), map()) :: map() | nil
@impl Jido.Plugin
def contribute(_topic, _config), do: nil
```

Add to `defoverridable`:

```elixir
contribute: 2
```

This is general-purpose — not tied to Identity. Any aggregator plugin can use it:

```elixir
# In Identity plugin's mount/2:
defp assemble_extensions(agent) do
  agent.__struct__.plugin_specs()
  |> Enum.reduce(%{}, fn spec, acc ->
    mod = spec.module
    if function_exported?(mod, :contribute, 2) do
      case mod.contribute(:identity_extensions, spec.config) do
        nil -> acc
        ext when is_map(ext) -> Map.put(acc, spec.name, ext)
      end
    else
      acc
    end
  end)
end
```

---

## Phase B: Strategy State as Default Plugin

**Effort: M (3–5 hours)**
**Depends on: Phase A**

### The Key Decision: Separate State Ownership from Execution

Strategy has two roles today:

1. **Execution engine** — `cmd/3`, `init/2`, `tick/2`, `snapshot/2`, `signal_routes/1`. This is the hot path. It stays as the `strategy:` agent option. No change.

2. **State ownership** — `agent.state[:__strategy__]` with `get/put/update/status/set_status`. This becomes a singleton default plugin.

The plugin does NOT execute `cmd/2`. It owns the state slice, provides schema defaults, and removes the hard-coded key from agent core awareness.

### B.1: Create `Jido.Agent.Strategy.StatePlugin`

**New file: `lib/jido/agent/strategy/state_plugin.ex`**

```elixir
defmodule Jido.Agent.Strategy.StatePlugin do
  @moduledoc """
  Default plugin that owns the `:__strategy__` state slice.

  Provides schema defaults and mount-time initialization for strategy state.
  Does NOT execute strategy logic — that remains the `strategy:` agent option.
  """

  use Jido.Plugin,
    name: "strategy_state",
    state_key: :__strategy__,
    singleton: true,
    actions: [],
    schema: Zoi.object(
      %{
        module: Zoi.atom(description: "The strategy module") |> Zoi.optional(),
        status: Zoi.atom(description: "Execution status") |> Zoi.default(:idle),
        result: Zoi.any(description: "Strategy result") |> Zoi.optional(),
        data: Zoi.any(description: "Strategy-specific data") |> Zoi.optional()
      },
      coerce: true
    )

  @impl Jido.Plugin
  def mount(agent, _config) do
    existing = Map.get(agent.state, :__strategy__)

    if existing do
      {:ok, nil}
    else
      {:ok, %{status: :idle}}
    end
  end
end
```

### B.2: Decouple `Jido.Await` from Hard-Coded Paths

**File: `lib/jido/await.ex`**

Current code hard-codes defaults:

```elixir
status_path: [:__strategy__, :status],
result_path: [:__strategy__, :result]
```

Replace with a lookup through the agent module:

```elixir
status_path: opts[:status_path] || default_status_path(agent_module),
result_path: opts[:result_path] || default_result_path(agent_module)
```

Where `default_status_path/1` resolves:

```elixir
defp default_status_path(agent_module) do
  if function_exported?(agent_module, :strategy_status_path, 0) do
    agent_module.strategy_status_path()
  else
    [:__strategy__, :status]
  end
end
```

**File: `lib/jido/agent.ex`** — add generated accessor:

```elixir
@doc "Returns the path to strategy status in agent state."
@spec strategy_status_path() :: [atom()]
def strategy_status_path, do: [:__strategy__, :status]

@doc "Returns the path to strategy result in agent state."
@spec strategy_result_path() :: [atom()]
def strategy_result_path, do: [:__strategy__, :result]
```

Add both to `defoverridable`. This lets custom strategy state plugins define different paths if needed.

### B.3: What Does NOT Change

| Call site | File | Change? |
|---|---|---|
| `strategy()` accessor | `agent.ex` | No |
| `strategy_opts()` accessor | `agent.ex` | No |
| `new/1` calls `strategy().init(agent, ctx)` | `agent.ex` | No — runs after plugin mount, so `:__strategy__` slice exists |
| `cmd/2` calls `strategy().cmd(agent, instructions, ctx)` | `agent.ex` | No — hot path untouched |
| `strategy_snapshot/1` | `agent.ex` | No |
| `AgentServer.post_init` calls `strategy.init()` | `agent_server.ex` | No — idempotent, strategy state slice already seeded |
| `SignalRouter.build/1` calls `strategy.signal_routes/1` | `signal_router.ex` | No |
| `AgentServer.status/1` calls `strategy_snapshot` | `agent_server.ex` | No |
| `Strategy.State` helper module | `strategy/state.ex` | No — still works, same key |

### B.4: What This Achieves

- `:__strategy__` is no longer a "magic" key — it's a plugin-owned state slice with a Zoi schema.
- Agent core (`agent.ex`) no longer needs to know about strategy state layout.
- `Jido.Await` no longer hard-codes reserved key paths.
- Strategy state gets schema defaults, making `get/put/update` calls safer.
- Custom strategy state plugins can override schema, mount behavior, and status paths.

---

## Phase C: Thread as Default Plugin

**Effort: S–M (2–4 hours)**
**Depends on: Phase A**

### C.1: Create `Jido.Thread.Plugin`

**New file: `lib/jido/thread/plugin.ex`**

```elixir
defmodule Jido.Thread.Plugin do
  @moduledoc """
  Default plugin that owns the `:__thread__` state slice.

  Thread storage is lazy by default — the state slice is `nil` until
  `Jido.Thread.Agent.ensure/2` is called. This avoids allocating a
  thread for agents that don't need one.
  """

  use Jido.Plugin,
    name: "thread",
    state_key: :__thread__,
    singleton: true,
    actions: []

  @impl Jido.Plugin
  def mount(_agent, _config) do
    # Lazy: don't allocate a thread until ensure/2 is called
    {:ok, nil}
  end
end
```

No schema — Thread stores a `%Jido.Thread{}` struct, not a plain map. The plugin's role is state slice ownership and compile-time registration, not schema validation of the Thread struct itself.

### C.2: Remove `:__thread__` Knowledge from Agent Core

**File: `lib/jido/agent.ex`** — `checkpoint/2` default implementation

Current:

```elixir
def checkpoint(agent, _ctx) do
  thread = agent.state[:__thread__]
  {:ok,
   %{
     version: 1,
     agent_module: __MODULE__,
     id: agent.id,
     state: Map.delete(agent.state, :__thread__),
     thread: thread && %{id: thread.id, rev: thread.rev}
   }}
end
```

Change to delegate thread extraction to `Jido.Persist` invariant enforcement (which already does this):

```elixir
def checkpoint(agent, _ctx) do
  {:ok,
   %{
     version: 1,
     agent_module: __MODULE__,
     id: agent.id,
     state: agent.state
   }}
end
```

`Jido.Persist.enforce_checkpoint_invariants/2` already strips `:__thread__` and creates the thread pointer. The agent default checkpoint no longer needs to duplicate that logic.

### C.3: Keep `Jido.Persist` As-Is (For Now)

`Jido.Persist` remains the invariant enforcer. It still:
- Strips `:__thread__` from checkpoint state
- Creates thread pointer (`%{id: id, rev: rev}`)
- Rehydrates thread on restore

This is correct behavior regardless of whether Thread is a plugin or a reserved key. The persist module enforces serialization invariants — that's its job.

Eventually (Phase D), persist can delegate to plugin hooks. But for now, keeping it unchanged is the low-risk path.

### C.4: `Jido.Thread.Agent` Helper — No Changes

The helper module continues to work identically:

```elixir
@key :__thread__
def get(%Agent{state: state}, default \\ nil), do: Map.get(state, @key, default)
def put(%Agent{} = agent, %Thread{} = thread), do: %{agent | state: Map.put(agent.state, @key, thread)}
```

Same key, same access pattern. The only difference is that `:__thread__` is now registered as a plugin-owned state slice rather than an informal convention.

---

## Phase D: Plugin Checkpoint Hooks (Optional, Future)

**Effort: L (1–2 days)**
**Not required for V2 launch. Do this when you have a third or fourth default plugin (Identity, Memory) and the pattern is clear.**

### Concept

Add optional plugin callbacks for checkpoint/restore participation:

```elixir
@callback on_checkpoint(plugin_state :: term(), context :: map()) ::
  {:externalize, key :: atom(), pointer :: term()} | :keep | :drop

@callback on_restore(pointer :: term(), context :: map()) ::
  {:ok, restored_state :: term()} | {:error, term()}
```

- `:externalize` — strip from checkpoint state, store pointer separately (Thread pattern)
- `:keep` — include in checkpoint state as-is (default)
- `:drop` — exclude from checkpoint (transient state)

The agent's generated `checkpoint/2` would pipeline through all plugins:

```elixir
def checkpoint(agent, ctx) do
  {state, externalized} =
    Enum.reduce(@plugin_specs, {agent.state, %{}}, fn spec, {state_acc, ext_acc} ->
      mod = spec.module
      plugin_state = Map.get(state_acc, spec.state_key)

      case mod.on_checkpoint(plugin_state, ctx) do
        {:externalize, key, pointer} ->
          {Map.delete(state_acc, spec.state_key), Map.put(ext_acc, key, pointer)}
        :drop ->
          {Map.delete(state_acc, spec.state_key), ext_acc}
        :keep ->
          {state_acc, ext_acc}
      end
    end)

  {:ok, Map.merge(%{version: 1, id: agent.id, state: state}, externalized)}
end
```

This removes ALL reserved key knowledge from agent core and persist. But it's complex — save it for when the pattern proves out with Strategy and Thread.

---

## Compile-Time vs Runtime Decision Map

| Concern | Compile-Time | Runtime | Rationale |
|---|---|---|---|
| Plugin instances (user + default) | **Yes** — `@plugin_instances` | — | Deterministic from agent module definition |
| Singleton validation | **Yes** — `CompileError` | Backstop in `Instance.new/1` | Fail fast at definition time |
| State key collision detection | **Yes** — `CompileError` | — | Already exists, extended for defaults |
| Plugin actions aggregation | **Yes** — `@plugin_actions` | — | Already exists, includes default plugins |
| Route expansion + conflict detection | **Yes** — `@validated_plugin_routes` | — | Already exists, includes default plugins |
| Schedule expansion | **Yes** — `@expanded_plugin_schedules` | — | Already exists |
| Requirements validation | **Yes** — `CompileError` | — | Already exists |
| Plugin capabilities union | **Yes** — `capabilities/0` | — | Already exists |
| `contribute/2` assembly | — | **Yes** — in `mount/2` | Runs once at agent creation, not hot path |
| Strategy execution (`cmd/3`) | — | **Yes** — hot path | Must be runtime (dynamic instructions) |
| Strategy state defaults | **Yes** — plugin schema | — | Zoi schema defaults at compile time |
| Status path resolution | **Yes** — `strategy_status_path/0` | — | Generated accessor, overridable |

**Principle:** Everything that CAN be computed at compile time SHOULD be. Runtime computation is reserved for `mount/2` (runs once) and `cmd/2` (must be dynamic).

---

## What NOT To Do

### Do NOT make Strategy a "real plugin" that executes `cmd/2`

The plugin system has no "wrap cmd" hook. Adding one would:
- Introduce ordering complexity on the hottest call path
- Blur the boundary between composition (plugins) and execution (strategy)
- Risk performance regression in `cmd/2`

Strategy execution stays as the `strategy:` agent option. The plugin only owns the state slice.

### Do NOT compute `capabilities.actions` at runtime

The original proposal suggested `agent.__struct__.actions()` at query time. But `actions/0` is already a compile-time accessor. When Identity arrives, its capabilities should reference the compile-time action list, not recompute it:

```elixir
# In Identity plugin mount/2 (when it arrives):
def mount(agent, _config) do
  actions = agent.__struct__.actions() |> Enum.map(&to_string/1)
  {:ok, %{capabilities: %{actions: actions}}}
end
```

This runs once at `new/1` time, using the compile-time list. Not truly "runtime computation" — it's a one-time copy of compile-time data into the state slice.

### Do NOT refactor `Jido.Persist` in Phase B or C

Persist's invariant enforcement is battle-tested. Keep it working exactly as-is while Thread becomes a plugin. Refactor persist only in Phase D (if ever), when you have plugin checkpoint hooks and multiple default plugins proving the pattern.

### Do NOT add `default_plugins: false` as a global kill switch (yet)

Start with per-plugin toggles (`thread_plugin: false`, `strategy_plugin: false`). A global kill switch introduces "completely bare agent" behavior that needs its own test matrix. Add it later if there's demand.

---

## Migration and Breakage Analysis

### Phase A: Plugin System Foundation

| What breaks | Who | Fix |
|---|---|---|
| Plugins with `singleton: true` + `as:` | Nobody (new feature) | N/A |
| State key collisions with new defaults | Anyone using `:__strategy__` or `:__thread__` as a user plugin state key | Rename their state key |

### Phase B: Strategy State Plugin

| What breaks | Who | Fix |
|---|---|---|
| Code hard-coding `[:__strategy__, :status]` path | `Jido.Await` | Use `agent_module.strategy_status_path()` |
| Agents that explicitly set `agent.state[:__strategy__]` in their own schema | Unlikely, but check | Remove from agent schema (plugin owns it now) |

### Phase C: Thread Plugin

| What breaks | Who | Fix |
|---|---|---|
| Agent `checkpoint/2` output format | Code calling `agent_module.checkpoint/2` directly (not via Persist) | Persist still enforces invariants; direct callers get raw state including `:__thread__` |
| Agents that explicitly set `:__thread__` in their own schema | Unlikely, but check | Remove from agent schema |

### All Phases: Backward Compatibility Guarantees

- `agent.state[:__strategy__]` still works — same key, same data
- `agent.state[:__thread__]` still works — same key, same data
- `Jido.Agent.Strategy.State` helper — unchanged API
- `Jido.Thread.Agent` helper — unchanged API
- `strategy()`, `strategy_opts()`, `cmd/2`, `strategy_snapshot/1` — unchanged
- All existing tests pass without modification (goal)

---

## File Change Summary

### Phase A (Foundation)

| File | Change |
|---|---|
| `lib/jido/plugin.ex` | Add `singleton` to config schema, accessor, `contribute/2` callback, defoverridable |
| `lib/jido/plugin/manifest.ex` | Add `singleton` field |
| `lib/jido/plugin/instance.ex` | Add singleton + `as:` guardrail in `new/1` |
| `lib/jido/agent.ex` | Default plugin auto-inclusion, singleton compile-time checks, opt-out options |

### Phase B (Strategy State)

| File | Change |
|---|---|
| `lib/jido/agent/strategy/state_plugin.ex` | **New file** — singleton plugin for `:__strategy__` |
| `lib/jido/await.ex` | Replace hard-coded paths with agent module accessors |
| `lib/jido/agent.ex` | Add `strategy_status_path/0`, `strategy_result_path/0` accessors |

### Phase C (Thread)

| File | Change |
|---|---|
| `lib/jido/thread/plugin.ex` | **New file** — singleton plugin for `:__thread__` |
| `lib/jido/agent.ex` | Simplify default `checkpoint/2` to not strip `:__thread__` (Persist handles it) |

### Tests (All Phases)

| File | Change |
|---|---|
| `test/jido/plugin/plugin_test.exs` | Add singleton validation tests |
| `test/jido/agent_plugin_integration_test.exs` | Add default plugin inclusion/exclusion tests |
| `test/jido/agent/strategy/state_plugin_test.exs` | **New** — singleton strategy state plugin tests |
| `test/jido/thread/plugin_test.exs` | **New** — singleton thread plugin tests |
| Existing agent/strategy tests | Should pass unchanged (backward compat) |

---

## Implementation Order

```
Phase A.1  Add singleton option to Plugin        (~1h)
Phase A.2  Compile-time singleton enforcement     (~1h)
Phase A.3  Default plugin auto-inclusion          (~2h)
Phase A.4  contribute/2 callback                  (~30min)
   ↓
Phase B.1  Strategy.StatePlugin                   (~1h)
Phase B.2  Decouple Await from hard-coded paths   (~1h)
Phase B.3  Verify all strategy tests pass         (~1h)
   ↓
Phase C.1  Thread.Plugin                          (~1h)
Phase C.2  Simplify agent checkpoint/2            (~30min)
Phase C.3  Verify all persist/thread tests pass   (~1h)
   ↓
Phase D    Plugin checkpoint hooks                (future, 1-2d)
```

Total estimated effort for A+B+C: **~10 hours** (spread across 2–3 focused sessions).
