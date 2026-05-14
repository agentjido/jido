# Plugins

<!-- covers: jido.plugins_and_sensors.plugin_mounting jido.plugins_and_sensors.plugin_lifecycle -->

**After:** You can compose multiple plugins with isolated state and understand lifecycle hooks.

> 🎓 **New to plugins?** Start with [Your First Plugin](your-first-plugin.md) for a hands-on tutorial before diving into this comprehensive reference.

Plugins are composable capability modules that extend an agent's functionality. They encapsulate actions, state, configuration, and signal routing into reusable units.

## When to Use Plugins

Use plugins when you want to:
- Package related actions together with their state
- Reuse capabilities across multiple agents
- Isolate state for a specific domain (e.g., chat, database, metrics)
- Define signal routing rules for a group of actions

## Defining a Plugin

```elixir
defmodule MyApp.ChatPlugin do
  use Jido.Plugin,
    name: "chat",
    state_key: :chat,
    actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
    schema: Zoi.object(%{
      messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
      model: Zoi.string() |> Zoi.default("gpt-4")
    }),
    signal_patterns: ["chat.*"],
    signal_routes: [
      {"chat.send", MyApp.Actions.SendMessage},
      {"chat.history", MyApp.Actions.ListHistory}
    ]
end
```

### Required Options

| Option | Description |
|--------|-------------|
| `name` | Plugin name (letters, numbers, underscores only) |
| `state_key` | Atom key for plugin state in agent's state map |
| `actions` | List of action modules the plugin provides |

### Optional Options

| Option | Description |
|--------|-------------|
| `description` | Human-readable description |
| `schema` | Zoi schema for plugin state defaults |
| `config_schema` | Zoi schema for per-agent configuration |
| `signal_patterns` | List of signal patterns for routing |
| `signal_routes` | Static signal route tuples (`{"type", Action}`) |
| `category`, `vsn`, `tags` | Metadata for organization |

## Using Plugins

Attach plugins to agents via the `plugins:` option:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    plugins: [
      MyApp.ChatPlugin,
      {MyApp.DatabasePlugin, %{pool_size: 5}}  # With config
    ]
end
```

Plugins are mounted during `new/1`. Each plugin's state is initialized under its `state_key`.

## State Isolation

Plugin state is nested under the plugin's `state_key`:

```elixir
# ChatPlugin with state_key: :chat
agent.state = %{
  chat: %{messages: [], model: "gpt-4"},  # ChatPlugin state
  database: %{pool_size: 5}               # DatabasePlugin state
}

# Access plugin state
chat_state = MyAgent.plugin_state(agent, :chat)
```

This prevents plugins from interfering with each other's state.

## Lifecycle Callbacks

All callbacks are optional with sensible defaults.

### Signal phases

AgentServer owns a fixed signal lifecycle. Plugins are the extension mechanism
for phase-specific behavior; AgentServer does not expose a generic middleware
chain.

```text
incoming signal
-> handle_signal/2
-> prepare_signal/2
-> route
-> prepare_action/3
-> Agent.cmd/3
-> directives queued
-> prepare_emit/2
-> dispatch
-> transform_result/3 on synchronous call return only
```

Plugins run in declaration order. `handle_signal/2`, `prepare_signal/2`, and
`prepare_action/3` are gated by `signal_patterns`. `prepare_emit/2` runs for
all plugins so outbound signing/encryption plugins can decide by pattern
matching the emitted signal.

### mount/2

Called during `new/1` to initialize plugin state. Pure function—no side effects.

```elixir
@impl Jido.Plugin
def mount(agent, config) do
  {:ok, %{initialized_at: DateTime.utc_now(), api_key: config[:api_key]}}
end
```

Returns `{:ok, map}` to merge into plugin state, or `{:error, reason}` to abort agent creation.

### signal_routes (compile-time)

Define signal-to-action routing rules declaratively in `use Jido.Plugin`:

```elixir
defmodule MyApp.ChatPlugin do
  use Jido.Plugin,
    name: "chat",
    state_key: :chat,
    actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
    signal_routes: [
      {"chat.send", MyApp.Actions.SendMessage},
      {"chat.history", MyApp.Actions.ListHistory}
    ]
end
```

Use the `signal_routes/1` callback only when routes must be computed from runtime config.

### handle_signal/2

Pre-routing hook called before signal routing. Can override or abort processing.

```elixir
@impl Jido.Plugin
def handle_signal(signal, context) do
  cond do
    signal.type == "admin.override" ->
      {:ok, {:override, MyApp.AdminAction}}
    blocked?(signal) ->
      {:error, :blocked}
    true ->
      {:ok, :continue}
  end
end
```

The `context` map contains `:agent`, `:agent_module`, `:plugin`, `:plugin_spec`, and `:config`.

### prepare_signal/2

Runs after `handle_signal/2` and before routing. Use it to verify, decrypt, or
canonicalize the effective signal and to attach trusted context for later phases.

```elixir
@impl Jido.Plugin
def prepare_signal(signal, context) do
  identity = verify_signature!(signal)
  {:ok, signal, %{identity: identity}}
end
```

The returned context delta is merged into accumulated `:trusted_context`.
Reserved runtime keys are rejected: `:state`, `:signal`, `:agent`,
`:agent_server_pid`, `:input_signal`, `:directive`, and `:dispatch`.
Duplicate top-level trusted context keys are also rejected.

### prepare_action/3

Runs after routing and before `Agent.cmd/3`. Use it to authorize the resolved
action against the prepared signal and accumulated trusted context.

```elixir
@impl Jido.Plugin
def prepare_action(_signal, {MyApp.AdminAction, _params}, context) do
  if "admin" in context.trusted_context.identity.scopes do
    {:ok, %{authorized?: true}}
  else
    {:error, :unauthorized}
  end
end
```

This hook cannot rewrite the signal or action. It returns additional trusted
context or fails closed.

### prepare_emit/2

Runs before an emitted signal is dispatched. Use it to sign, encrypt, enrich, or
reroute outbound signals. Its context includes `:input_signal`,
`:trusted_context`, `:directive`, `:dispatch`, plugin metadata, agent metadata,
`:jido_instance`, and `:partition`.

```elixir
@impl Jido.Plugin
def prepare_emit(signal, context) do
  encrypted = encrypt_for_dispatch(signal, context.dispatch)
  {:ok, encrypted}
end
```

Return `{:ok, signal}` to keep the current dispatch or `{:ok, signal, dispatch}`
to rewrite dispatch.

### transform_result/3

Transforms the agent returned from `AgentServer.call/3` (synchronous path only).
This is a caller-view hook, not a security hook; failures are logged and the
agent is returned unchanged.

```elixir
@impl Jido.Plugin
def transform_result(_action, agent, _context) do
  new_state = Map.put(agent.state, :last_call_at, DateTime.utc_now())
  %{agent | state: new_state}
end
```

### child_spec/1

Returns child process specifications started during `AgentServer.init/1`.

```elixir
@impl Jido.Plugin
def child_spec(config) do
  %{id: MyWorker, start: {MyWorker, :start_link, [config]}}
end
```

Return `nil` for no children, a single spec, or a list of specs.

## Composing Multiple Plugins

Agents can use multiple plugins with isolated state:

```elixir
defmodule MyAssistant do
  use Jido.Agent,
    name: "assistant",
    plugins: [
      MyApp.ChatPlugin,
      MyApp.MemoryPlugin,
      {MyApp.ToolsPlugin, %{enabled_tools: [:search, :calculator]}}
    ]
end
```

Each plugin maintains its own state slice and routing rules. Plugins are mounted in order, so later plugins can depend on state from earlier ones.

## Default Plugins

Jido ships with **default plugins** that are automatically included in every agent. These are framework-provided singleton plugins that handle core concerns.

### Built-in Defaults

| Plugin | State Key | Purpose |
|--------|-----------|---------|
| `Jido.Agent.Identity.Plugin` | `:__identity__` | Agent identity: profile, lifecycle facts |
| `Jido.Thread.Plugin` | `:__thread__` | Conversation thread management |
| `Jido.Memory.Plugin` | `:__memory__` | On-demand memory container for agent cognitive state |

Default plugins are **singletons** — only one instance per state key. They are mounted during `new/1` like any other plugin, but they don't initialize state by default. State is created on demand using helpers like `Jido.Agent.Identity.Agent.ensure/2` and `Jido.Memory.Agent.ensure/2`.

`Jido.Pod` also uses this mechanism for pod-wrapped agents: it injects a
singleton plugin under the reserved `:__pod__` key. That plugin is not a
framework-wide default for all agents, but pod agents can still replace it via
the normal `default_plugins: %{__pod__: ...}` override path.

### Identity Plugin

The identity plugin gives every agent a first-class profile/lifecycle state
primitive stored at `agent.state[:__identity__]`. The state key remains the
canonical identity storage key; the struct and helper modules now live under
`Jido.Agent.Identity` so `Jido.Identity` can be used by top-level identity
extensions, including the separate `jido_identity` package.

The default plugin keeps the existing `identity` metadata name and `:identity`
capability because plugin ownership remains anchored on `:__identity__`.

#### Naming and Migration

The rename separates two concepts that previously shared the same namespace:

| Concept | API owner |
|---------|-----------|
| Agent identity state: profile, age, origin, generation, revision | `Jido.Agent.Identity` |
| Top-level identity extensions: keys, principals, signatures, attestations | `Jido.Identity` in a separate identity package |

For built-in identity helpers, update these names:

| Before | After |
|--------|-------|
| `Jido.Identity` | `Jido.Agent.Identity` |
| `Jido.Identity.Agent` | `Jido.Agent.Identity.Agent` |
| `Jido.Identity.Profile` | `Jido.Agent.Identity.Profile` |
| `Jido.Identity.Actions.Evolve` | `Jido.Agent.Identity.Actions.Evolve` |
| `Jido.Identity.Agent.has_identity?/1` | `Jido.Agent.Identity.Agent.has_identity?/1` |

These surfaces intentionally do not change:

- Agent state still stores the identity at `agent.state[:__identity__]`.
- Default plugin overrides still use `default_plugins: %{__identity__: ...}`.
- The default plugin metadata name remains `identity`.
- The default plugin capability remains `:identity`.
- The evolve action metadata name remains `identity_evolve`.

```elixir
alias Jido.Agent.Identity.Agent, as: IdentityAgent
alias Jido.Agent.Identity.Profile

agent = MyAgent.new()

# Identity state is not initialized until you ask for it
refute IdentityAgent.has_identity?(agent)

# Initialize on demand
agent = IdentityAgent.ensure(agent, profile: %{age: 0, origin: :spawned})

# Read profile data
Profile.age(agent)    #=> 0
Profile.get(agent, :origin)  #=> :spawned

# Evolve identity profile facts over simulated time
{agent, []} = MyAgent.cmd(agent, {Jido.Agent.Identity.Actions.Evolve, %{years: 3}})
Profile.age(agent)    #=> 3
```

To fully replace the default identity with your own implementation, define a custom plugin that uses the same state key:

```elixir
defmodule MyApp.CustomIdentityPlugin do
  use Jido.Plugin,
    name: "custom_identity",
    state_key: :__identity__,
    actions: [],
    description: "Custom identity with auto-initialization."

  @impl Jido.Plugin
  def mount(_agent, config) do
    profile = Map.get(config, :profile, %{age: 0})
    {:ok, Jido.Agent.Identity.new(profile: profile)}
  end
end

defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    default_plugins: %{
      __identity__: {MyApp.CustomIdentityPlugin, %{profile: %{age: 5, origin: :configured}}}
    }
end
```

Persisted checkpoints from earlier Jido releases may still contain a
`%Jido.Identity{}` struct at `:__identity__`. `Jido.Persist.thaw/3` migrates
that value to `%Jido.Agent.Identity{}` automatically during restore. For
custom storage or manual checkpoint handling, use
`Jido.Agent.Identity.migrate_legacy/1`,
`Jido.Agent.Identity.migrate_state/1`, or
`Jido.Agent.Identity.migrate_checkpoint/1`.

The migration only converts the exact old core agent identity struct shape
(`rev`, `profile`, `created_at`, and `updated_at`). Other values under
`:__identity__`, including custom plugin state or top-level `Jido.Identity`
extension structs, are left unchanged. Jido does not provide deprecated
`Jido.Identity` shim modules because keeping those modules would continue to
claim the top-level namespace this rename frees.

### Thread Plugin

The Thread plugin stores `agent.state[:__thread__]` as an append-only journal of
what happened. Thread entries should be treated as immutable facts.

If external metadata arrives later, append a follow-up entry that points back
to the original entry instead of updating it in place. The caller supplies a
stable `entry_id` up front so later events can reference it:

```elixir
alias Jido.Thread.Agent, as: ThreadAgent

entry_id = "entry_" <> Jido.Util.generate_id()

agent =
  ThreadAgent.append(agent, %{
    id: entry_id,
    kind: :message,
    payload: %{role: "assistant", content: "hello"}
  })

agent =
  ThreadAgent.append(agent, %{
    kind: :message_committed,
    payload: %{provider: :slack, remote_id: slack_ts},
    refs: %{entry_id: entry_id}
  })
```

This is the preferred way to model late provider acknowledgements, delivery
receipts, and similar metadata while preserving thread history. For the
rationale and a more general pattern, see
[Persistence & Storage](storage.md#modeling-late-metadata-with-follow-up-events).

### Memory Plugin

The Memory plugin gives every agent an on-demand cognitive memory container stored at `agent.state[:__memory__]`. Memory is organized into **spaces** — named containers holding either map (key-value) or list (ordered items) data. Two reserved spaces, `:world` and `:tasks`, are created by default. Domain-specific wrappers should be built in your own modules on top of the generic space primitives.

The built-in plugin is deliberately minimal. Packages that provide their own
memory implementation should use the same `:__memory__` state key and replace
the default through `default_plugins:`, not by mounting a second memory plugin
in `plugins:`.

```elixir
alias Jido.Memory.Agent, as: MemoryAgent

agent = MyAgent.new()

# Memory is not initialized until you ask for it
refute MemoryAgent.has_memory?(agent)

# Initialize on demand
agent = MemoryAgent.ensure(agent)

# Work with map spaces (e.g. :world)
agent = MemoryAgent.put_in_space(agent, :world, :temperature, 22)
MemoryAgent.get_in_space(agent, :world, :temperature)  #=> 22

# Work with list spaces (e.g. :tasks)
agent = MemoryAgent.append_to_space(agent, :tasks, %{id: "t1", text: "Check sensor"})
```

### Overriding and Disabling Defaults

Default plugins can be controlled per-agent using the `default_plugins:` option with a map keyed by state key:

```elixir
# Disable identity state (keep thread)
use Jido.Agent,
  name: "minimal",
  default_plugins: %{__identity__: false}

# Replace with custom module
use Jido.Agent,
  name: "custom",
  default_plugins: %{__identity__: MyApp.CustomIdentityPlugin}

# Replace with custom module and config
use Jido.Agent,
  name: "configured",
  default_plugins: %{__identity__: {MyApp.CustomIdentityPlugin, %{profile: %{age: 10}}}}

# Replace memory while preserving the canonical :__memory__ state key
use Jido.Agent,
  name: "persistent_memory",
  default_plugins: %{__memory__: {MyApp.PersistentMemoryPlugin, %{store: MyApp.Store}}}

# Disable memory (keep others)
use Jido.Agent,
  name: "no_memory",
  default_plugins: %{__memory__: false}

# Disable all defaults
use Jido.Agent,
  name: "bare",
  default_plugins: false
```

> **Note:** `default_plugins:` only controls built-in defaults. To add new plugins, use the `plugins:` option.

For pod-wrapped agents, the reserved `:__pod__` plugin can be replaced but
should not be disabled. See [Pods](pods.md) for the pod-specific contract.

## See Also

See `Jido.Plugin` moduledoc for complete API reference and advanced patterns.

> **AI-powered plugins:** For LLM-integrated plugins, see the [jido_ai documentation](https://hexdocs.pm/jido_ai).
