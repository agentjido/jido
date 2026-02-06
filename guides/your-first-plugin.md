# Your First Plugin

**After:** You can refactor "stuff your agent does" into a Plugin with isolated state and routing.

## The Result

Here's what you'll build—a `CounterPlugin` that tracks a counter in isolated state and routes signals to increment it:

```elixir
defmodule MyApp.CounterPlugin do
  use Jido.Plugin,
    name: "counter",
    state_key: :counter,
    actions: [MyApp.IncrementAction],
    schema: Zoi.object(%{
      value: Zoi.integer() |> Zoi.default(0),
      last_updated: Zoi.any() |> Zoi.optional()
    }),
    signal_patterns: ["counter.*"]

  @impl Jido.Plugin
  def router(_config) do
    [{"counter.increment", MyApp.IncrementAction}]
  end
end
```

Attach it to an agent:

```elixir
defmodule MyApp.MyAgent do
  use Jido.Agent,
    name: "my_agent",
    plugins: [MyApp.CounterPlugin]
end
```

Send a signal:

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: MyApp.MyAgent, jido: MyApp.Jido)

signal = Jido.Signal.new!("counter.increment", %{amount: 5}, source: "/app")
{:ok, agent} = Jido.AgentServer.call(pid, signal)

agent.state.counter.value
#=> 5
```

The plugin owns `agent.state.counter`—isolated from other plugins.

## Building It Step by Step

### Step 1: Create the Action

Actions do the actual work. This action increments a counter:

```elixir
defmodule MyApp.IncrementAction do
  use Jido.Action,
    name: "increment",
    schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

  alias Jido.Agent.StateOp

  def run(%{amount: amount}, %{state: state}) do
    current = get_in(state, [:counter, :value]) || 0

    {:ok, %{},
     [
       %StateOp.SetPath{path: [:counter, :value], value: current + amount},
       %StateOp.SetPath{path: [:counter, :last_updated], value: DateTime.utc_now()}
     ]}
  end
end
```

### Step 2: Define the Plugin

Wrap the action in a plugin with state and routing:

```elixir
defmodule MyApp.CounterPlugin do
  use Jido.Plugin,
    name: "counter",
    state_key: :counter,
    actions: [MyApp.IncrementAction],
    schema: Zoi.object(%{
      value: Zoi.integer() |> Zoi.default(0),
      last_updated: Zoi.any() |> Zoi.optional()
    }),
    signal_patterns: ["counter.*"]

  @impl Jido.Plugin
  def router(_config) do
    [{"counter.increment", MyApp.IncrementAction}]
  end
end
```

**Required options:**

| Option | Description |
|--------|-------------|
| `name` | Plugin name (letters, numbers, underscores) |
| `state_key` | Atom key for plugin state in agent |
| `actions` | List of action modules the plugin provides |

**Key optional options:**

| Option | Description |
|--------|-------------|
| `schema` | Zoi schema for plugin state with defaults |
| `signal_patterns` | Patterns this plugin handles (e.g., `"counter.*"`) |

### Step 3: Attach to an Agent

```elixir
defmodule MyApp.MyAgent do
  use Jido.Agent,
    name: "my_agent",
    plugins: [MyApp.CounterPlugin]
end
```

When the agent is created, the plugin's state is initialized under its `state_key`.

## State Isolation

Each plugin gets its own namespace in `agent.state`:

```elixir
agent = MyApp.MyAgent.new()

agent.state
#=> %{
#=>   counter: %{value: 0, last_updated: nil}  # CounterPlugin state
#=> }
```

With multiple plugins:

```elixir
defmodule MyApp.MultiPluginAgent do
  use Jido.Agent,
    name: "multi_agent",
    plugins: [
      MyApp.CounterPlugin,
      MyApp.ChatPlugin
    ]
end

agent = MyApp.MultiPluginAgent.new()

agent.state
#=> %{
#=>   counter: %{value: 0, last_updated: nil},  # CounterPlugin
#=>   chat: %{messages: [], model: "gpt-4"}     # ChatPlugin
#=> }
```

Plugins can't accidentally overwrite each other's state.

## Signal Routing

The `router/1` callback maps signal types to actions:

```elixir
@impl Jido.Plugin
def router(_config) do
  [
    {"counter.increment", MyApp.IncrementAction},
    {"counter.reset", MyApp.ResetAction}
  ]
end
```

When a signal arrives:

1. Router finds a matching pattern
2. The corresponding action runs via `cmd/2`
3. State operations update `agent.state`

**Complete example:**

```elixir
# Start the agent
{:ok, pid} = Jido.AgentServer.start_link(agent: MyApp.MyAgent, jido: MyApp.Jido)

# Send increment signal
signal = Jido.Signal.new!("counter.increment", %{amount: 10}, source: "/app")
{:ok, agent} = Jido.AgentServer.call(pid, signal)

agent.state.counter.value
#=> 10

# Send another
signal = Jido.Signal.new!("counter.increment", %{amount: 5}, source: "/app")
{:ok, agent} = Jido.AgentServer.call(pid, signal)

agent.state.counter.value
#=> 15
```

## Configuration

Pass per-agent configuration with the `{Plugin, config}` form:

```elixir
defmodule MyApp.ConfigurablePlugin do
  use Jido.Plugin,
    name: "configurable",
    state_key: :configurable,
    actions: [MyApp.SomeAction],
    config_schema: Zoi.object(%{
      max_value: Zoi.integer() |> Zoi.default(100)
    })

  @impl Jido.Plugin
  def mount(_agent, config) do
    {:ok, %{initialized_at: DateTime.utc_now(), max: config[:max_value]}}
  end
end
```

Attach with config:

```elixir
defmodule MyApp.ConfiguredAgent do
  use Jido.Agent,
    name: "configured_agent",
    plugins: [
      {MyApp.ConfigurablePlugin, %{max_value: 500}}
    ]
end

agent = MyApp.ConfiguredAgent.new()
agent.state.configurable.max
#=> 500
```

The `mount/2` callback receives the config and can use it to initialize state.

## Next Steps

- [Plugins Reference](plugins.md) — Full API reference and lifecycle callbacks
- [Signals & Routing](signals.md) — Signal patterns and routing rules
- [Actions](actions.md) — How actions transform state and emit directives
