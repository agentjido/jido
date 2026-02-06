# Proposal: Default Plugins as the Universal Composition Mechanism

## Summary

This proposal argues that `Jido.Identity` — and eventually other "reserved key" primitives like `__thread__`, `__memory__`, and `__strategy__` — should be implemented as **default plugins** rather than ad hoc reserved keys with standalone helper modules. The goal is to keep the agent core minimal (four functions: `new/1`, `set/2`, `validate/2`, `cmd/2`) while proving that the plugin system is robust enough to serve as the universal composition layer for both framework primitives and user extensions.

---

## The Problem: Reserved Key Sprawl

Today, the agent core carries knowledge about several reserved state keys:

| Key | Where Core Knows About It |
|---|---|
| `__thread__` | `checkpoint/2` strips it during serialization |
| `__strategy__` | `Jido.Await` hard-codes path `[:__strategy__, :status]`; strategy init runs in `new/1` |
| `__parent__` | `AgentServer.State` writes it during child spawn |

Each reserved key follows the same pattern: a well-known atom in `agent.state`, a helper module (`Jido.Thread.Agent`, `Jido.Agent.Strategy.State`) with `get/put/update/ensure`, and one or two special-case references in agent core code.

Identity would add another: `__identity__` with `Jido.Identity.Agent`. Each addition makes the agent core a little less minimal and a little more aware of domain concerns it shouldn't need to know about.

---

## The Observation: Plugins Already Do This

A plugin with `state_key: :__identity__` and a helper module is *structurally identical* to the reserved key pattern:

| Reserved Key Pattern | Plugin Pattern |
|---|---|
| `@key :__identity__` | `state_key: :__identity__` |
| `Jido.Identity.Agent.get(agent)` | `agent.state[:__identity__]` (same) |
| `Jido.Identity.Agent.ensure(agent)` | `mount/2` seeds defaults |
| Standalone helper module | Plugin module + companion helper |
| Manual state init in `new/1` | Plugin mount runs automatically |
| No schema validation | Zoi schema with defaults |
| No config resolution | 3-layer config merge |
| Must manually add actions | Actions declared in plugin |
| No signal routing | Routes declared in plugin |

The plugin system already provides schema-validated state slices, automatic mount hooks, config resolution, action aggregation, signal routing, child process management, and compile-time validation. The reserved key pattern provides none of that — it's just a convention.

---

## The Proposal

### 1. Identity as a Default Plugin

Ship `Jido.Identity.Plugin` as a framework-provided plugin that is auto-included by `use Jido.Agent` (overridable):

```elixir
defmodule Jido.Identity.Plugin do
  use Jido.Plugin,
    name: "identity",
    state_key: :__identity__,
    singleton: true,
    actions: [Jido.Identity.Actions.Evolve],
    schema: Zoi.object(%{
      rev: Zoi.integer() |> Zoi.default(0),
      profile: Zoi.map() |> Zoi.default(%{age: nil}),
      capabilities: Zoi.map() |> Zoi.default(%{
        tags: [],
        io: %{},
        limits: %{}
      }),
      extensions: Zoi.map() |> Zoi.default(%{}),
      created_at: Zoi.integer() |> Zoi.optional(),
      updated_at: Zoi.integer() |> Zoi.optional()
    })

  @impl Jido.Plugin
  def mount(agent, _config) do
    now = System.system_time(:millisecond)

    # Pull identity extensions from other mounted plugins
    extensions = assemble_extensions(agent)

    {:ok, %{
      created_at: now,
      updated_at: now,
      extensions: extensions
    }}
  end

  defp assemble_extensions(agent) do
    # Iterate plugin specs, call identity_extension/1 on each
    # that exports it, assemble into namespaced map
    ...
  end
end
```

Note: `capabilities.actions` is intentionally *not stored*. It's computed at query time from `agent.__struct__.actions()`. Derived data should be derived, not cached.

### 2. Agent Auto-Includes Default Plugins

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    plugins: [
      # User plugins
      MyApp.ChatPlugin
    ]
    # Jido.Identity.Plugin is auto-included unless explicitly excluded
end
```

Agent authors who want a custom identity implementation swap it:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    identity: MyApp.CustomIdentityPlugin,  # replaces default
    plugins: [MyApp.ChatPlugin]
end
```

Same contract, different implementation. No extra tech debt.

### 3. Helper Module Remains Unchanged

`Jido.Identity.Agent` still provides the ergonomic API (`get/put/ensure/snapshot/supports_action?`). It accesses `agent.state[:__identity__]` — same as today's reserved key pattern. The difference is that the *storage and initialization* are managed by the plugin system rather than by ad hoc code in the agent core.

```elixir
# These work identically whether Identity is a reserved key or a default plugin:
Identity.Agent.capabilities(agent)
Identity.Agent.supports_action?(agent, "MyApp.Actions.FetchURL")
Identity.Agent.has_tag?(agent, :web)
Identity.Agent.snapshot(agent)
```

---

## Required Plugin System Changes

Three small additions to the plugin system make this work. Total estimated effort: ~50 lines of framework code.

### Change 1: Singleton Plugins

**Problem:** Plugins can be multi-instanced via `as:`, which would change `state_key` from `:__identity__` to `:__identity___support`. Default plugins need a fixed, unaliasable key.

**Solution:** Add `singleton: true` to the plugin config schema. The agent macro enforces:
- Cannot use `as:` with singleton plugins
- Cannot mount more than one instance
- `state_key` is always exactly as declared

```elixir
use Jido.Plugin,
  name: "identity",
  state_key: :__identity__,
  singleton: true,  # new option
  actions: [...]
```

**Agent macro validation (~10 lines):**
```elixir
# In agent compile-time setup, after normalizing instances:
singleton_violations =
  @plugin_instances
  |> Enum.filter(fn inst -> inst.module.singleton?() and inst.as != nil end)

if singleton_violations != [] do
  raise CompileError, description: "Cannot alias singleton plugins: ..."
end
```

### Change 2: Identity Extension Callback (Pull-Based)

**Problem:** The Identity design wants plugins to contribute extension data (e.g., CharacterPlugin adds persona/voice to Identity's extensions). But `mount/2` can only write to its own state slice — Plugin A can't write to Plugin B's state.

**Solution:** Add an optional callback `identity_extension/1` to the Plugin behaviour. The Identity plugin *pulls* contributions during its own mount, rather than other plugins *pushing* into Identity's state.

```elixir
# In Jido.Plugin behaviour:
@callback identity_extension(config :: map()) :: map() | nil
# Default: nil (no contribution)

# In Jido.Identity.Plugin.mount/2:
defp assemble_extensions(agent) do
  agent.__struct__.plugin_specs()
  |> Enum.reduce(%{}, fn spec, acc ->
    mod = spec.module
    if function_exported?(mod, :identity_extension, 1) do
      case mod.identity_extension(spec.config) do
        nil -> acc
        ext when is_map(ext) -> Map.put(acc, spec.name, ext)
      end
    else
      acc
    end
  end)
end
```

This is more functional: data flows in one direction (from plugins → Identity), and Identity assembles the composite. No cross-slice mutation.

**Plugin usage:**
```elixir
defmodule MyApp.CharacterPlugin do
  use Jido.Plugin,
    name: "character",
    state_key: :character,
    actions: [SetPersona, SetVoice, Evolve]

  @impl Jido.Plugin
  def identity_extension(config) do
    %{
      persona: config[:persona] || %{},
      voice: config[:voice] || %{},
      __public__: %{
        persona: Map.take(config[:persona] || %{}, [:role]),
        voice: Map.take(config[:voice] || %{}, [:tone])
      }
    }
  end
end
```

### Change 3: Compute Capabilities Instead of Storing Them

**Problem:** The Identity design stores `capabilities.actions` — the list of actions the agent supports. But this list drifts if plugins are added/removed, and there's no hook to auto-sync.

**Solution:** Don't store it. Compute it at query time.

```elixir
defmodule Jido.Identity.Agent do
  def actions(agent) do
    agent.__struct__.actions()
  end

  def supports_action?(agent, action_id) do
    action_str = to_string(action_id)
    Enum.any?(actions(agent), fn a -> to_string(a) == action_str end)
  end

  def capabilities(agent) do
    identity = get(agent)
    stored = identity.capabilities

    # Merge stored metadata with computed action list
    Map.put(stored, :actions, actions(agent))
  end

  def snapshot(agent) do
    identity = get(agent)
    %{
      capabilities: capabilities(agent),
      profile: Map.take(identity.profile, [:age, :generation, :origin]),
      extensions: public_extensions(identity.extensions)
    }
  end
end
```

This is better FP: derived data is a function of the source, not a copy that must be kept in sync.

---

## What This Unlocks

### For Framework Authors

The agent core shrinks. `agent.ex` doesn't need to know about Identity, Thread, Memory, or any domain concept. It defines the update algebra and delegates everything else to the composition layer.

Over time, other reserved keys could migrate:

| Reserved Key | Migration Path | Difficulty |
|---|---|---|
| `__identity__` | Default plugin (this proposal) | Low |
| `__thread__` | Default plugin; `checkpoint/2` becomes a plugin callback | Medium |
| `__memory__` | Default plugin (not yet implemented, clean slate) | Low |
| `__strategy__` | Harder — deeply coupled to `cmd/2` hot path | High |
| `__parent__` | Set by AgentServer, not agent core; could be a plugin field | Low |

### For SDK Users

Swapping implementations becomes trivial. Want a richer identity system? Write a plugin that follows the same contract:

```elixir
defmodule MyApp.EnterpriseIdentity do
  use Jido.Plugin,
    name: "identity",
    state_key: :__identity__,
    singleton: true,
    actions: [MyApp.Identity.Evolve, MyApp.Identity.Sync],
    schema: my_richer_schema(),
    config_schema: Zoi.object(%{
      identity_provider: Zoi.string(),
      sync_interval_ms: Zoi.integer() |> Zoi.default(60_000)
    })

  @impl Jido.Plugin
  def mount(agent, config) do
    # Custom initialization — fetch from identity provider, etc.
    ...
  end
end

defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    identity: MyApp.EnterpriseIdentity
end
```

No framework changes needed. No forking. No monkey-patching. The plugin contract is the only interface.

### For the Plugin System

This is the "eat your own dogfood" moment. If the framework's own primitives can be expressed as plugins, the plugin system is validated as a genuine composition mechanism — not just an extension point.

---

## Design Principles at Work

### 1. Data > Functions > Macros

Identity as a plugin is **data-driven**: a Zoi schema declares the shape, `mount/2` returns a map, actions transform state via `cmd/2`. No special macros, no reserved-key magic.

### 2. Composition Over Inheritance

Plugins compose orthogonally. An agent with Identity + Thread + Chat has three independent state slices, three independent mount hooks, three independent action sets. No diamond inheritance, no method resolution order.

### 3. Derived Data Should Be Derived

`capabilities.actions` is computed from `agent.__struct__.actions()`, not stored and synced. `snapshot/1` assembles a view at call time. The stored state contains only source-of-truth data.

### 4. The Core Should Be Boring

The ideal agent core is: struct definition, `new/1`, `set/2`, `validate/2`, `cmd/2`. Everything interesting happens in plugins and strategies. The core's job is to be a reliable, minimal foundation — not to accumulate domain concepts.

---

## Risks and Mitigations

### Risk: Plugin System Becomes Load-Bearing

If framework primitives depend on the plugin system, bugs in plugin mounting, config resolution, or compile-time validation have broader blast radius.

**Mitigation:** The plugin system is already load-bearing for user code. Making framework code use the same path increases test coverage and surfaces issues faster.

### Risk: Plugin Mount Order Matters

Identity needs to mount *after* other plugins so it can pull their `identity_extension/1` contributions.

**Mitigation:** Default plugins mount last. The agent macro appends default plugins after user-declared plugins. This is explicit and documented.

### Risk: Backward Compatibility

Existing code using `agent.state[:__identity__]` (if any) would break if the key changes.

**Mitigation:** The key doesn't change. `state_key: :__identity__` produces exactly the same state layout. The helper module API is identical. The only change is *who manages initialization*.

### Risk: Singleton Semantics Are New

The plugin system doesn't have `singleton: true` today. Adding it introduces a new concept.

**Mitigation:** It's a compile-time-only concept — a validation check in the agent macro, not a runtime behavior change. ~10 lines of code.

---

## Implementation Plan

### Phase 1: Plugin System Changes (S effort, ~2 hours)

1. Add `singleton: true` option to plugin config schema
2. Add `singleton?/0` accessor to generated plugin functions
3. Add agent macro validation: no `as:` on singletons, no duplicate singletons
4. Add optional `identity_extension/1` callback with `nil` default

### Phase 2: Identity Plugin (M effort, ~4 hours)

1. `Jido.Identity` struct (unchanged from JIDO_IDENTITY.md)
2. `Jido.Identity.Plugin` — default plugin with schema, mount, extension assembly
3. `Jido.Identity.Agent` — helper module (unchanged API)
4. `Jido.Identity.Actions.Evolve` — action module
5. Agent macro auto-includes Identity plugin, `identity:` option to override
6. Unit tests

### Phase 3: Validation (S effort, ~2 hours)

1. Integration test: agent with default Identity + user plugins with extensions
2. Integration test: agent with swapped custom Identity plugin
3. Integration test: multi-agent orchestrator using `Identity.Agent.supports_action?/2`
4. Verify `snapshot/1` with `__public__` projection

### Phase 4: Migration Path for Existing Reserved Keys (Future, Optional)

1. Evaluate `__thread__` as default plugin candidate
2. Evaluate `__memory__` as default plugin candidate
3. Document the "default plugin" pattern for SDK authors

---

## Conclusion

The question isn't "can Identity be a plugin?" — it clearly can, with minimal changes. The real question is "should framework primitives use the same composition mechanism as user extensions?" The answer, from a functional programming perspective, is yes: a single, well-tested composition mechanism is better than two parallel systems (plugins for users, reserved keys for the framework) that do the same thing differently.

The cost is ~50 lines of plugin system code (singleton validation + identity extension callback). The payoff is a trimmer agent core, a validated plugin system, and a clean swap path for SDK authors who outgrow the default Identity implementation.
