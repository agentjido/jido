# Plugins

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
    signal_patterns: ["chat.*"]
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

### mount/2

Called during `new/1` to initialize plugin state. Pure function—no side effects.

```elixir
@impl Jido.Plugin
def mount(agent, config) do
  {:ok, %{initialized_at: DateTime.utc_now(), api_key: config[:api_key]}}
end
```

Returns `{:ok, map}` to merge into plugin state, or `{:error, reason}` to abort agent creation.

### router/1

Defines signal-to-action routing rules.

```elixir
@impl Jido.Plugin
def router(_config) do
  [
    {"chat.send", MyApp.Actions.SendMessage},
    {"chat.history", MyApp.Actions.ListHistory}
  ]
end
```

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

### transform_result/3

Transforms the agent returned from `AgentServer.call/3` (synchronous path only).

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
| `Jido.Identity.Plugin` | `:__identity__` | Agent self-model: profile, lifecycle facts |
| `Jido.Thread.Plugin` | `:__thread__` | Conversation thread management |
| `Jido.Memory.Plugin` | `:__memory__` | On-demand memory container for agent cognitive state |

Default plugins are **singletons** — only one instance per state key. They are mounted during `new/1` like any other plugin, but they don't initialize state by default. State is created on demand using helpers like `Jido.Identity.Agent.ensure/2` and `Jido.Memory.Agent.ensure/2`.

### Identity Plugin

The Identity plugin gives every agent a first-class identity primitive stored at `agent.state[:__identity__]`. Identity tracks profile facts (age, origin, generation) and a monotonic revision counter.

```elixir
alias Jido.Identity.Agent, as: IdentityAgent
alias Jido.Identity.Profile

agent = MyAgent.new()

# Identity is not initialized until you ask for it
refute IdentityAgent.has_identity?(agent)

# Initialize on demand
agent = IdentityAgent.ensure(agent, profile: %{age: 0, origin: :spawned})

# Read profile data
Profile.age(agent)    #=> 0
Profile.get(agent, :origin)  #=> :spawned

# Evolve identity over simulated time
{agent, []} = MyAgent.cmd(agent, {Jido.Identity.Actions.Evolve, %{years: 3}})
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
    {:ok, Jido.Identity.new(profile: profile)}
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

### Memory Plugin

The Memory plugin gives every agent an on-demand cognitive memory container stored at `agent.state[:__memory__]`. Memory is organized into **spaces** — named containers holding either map (key-value) or list (ordered items) data. Two reserved spaces, `:world` and `:tasks`, are created by default. Domain-specific wrappers should be built in your own modules on top of the generic space primitives.

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
# Disable identity (keep thread)
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

## See Also

See `Jido.Plugin` moduledoc for complete API reference and advanced patterns.

> **AI-powered plugins:** For LLM-integrated plugins, see the [jido_ai documentation](https://hexdocs.pm/jido_ai).
