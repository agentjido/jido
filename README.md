<p align="center">
  <h1>Jido (自動)</h1>
</p>

<p align="center">
  自動 (Jido) - A flexible framework for building distributed Agents and Workflows in Elixir.
</p>

<p align="center">
  <a href="https://hex.pm/packages/jido">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/jido.svg">
  </a>

  <a href="https://hexdocs.pm/jido">
    <img alt="Hex Docs" src="http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat">
  </a>

  <a href="https://github.com/agentjido/jido/actions">
    <img alt="CI Status" src="https://github.com/agentjido/jido/workflows/ci/badge.svg">
  </a>

  <a href="https://opensource.org/licenses/Apache-2.0">
    <img alt="Apache 2 License" src="https://img.shields.io/hexpm/l/jido">
  </a>
</p>

## Features

- **Actions**: Discrete, composable units of functionality with consistent interfaces
- **Workflows**: Robust execution runtime with logging, telemetry, and error handling
- **Agents**: Stateful autonomous entities that can plan and execute workflows
- **Sensors**: Event-driven data gathering components
- **Signals**: Cloud Events-based messaging between components
- **Flexible Planning**: Pluggable planners for agent decision making
- **Comprehensive Testing**: Rich testing tools and helpers
- **Observable**: Built-in telemetry and debugging tools

## Installation

Add `jido` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 0.1.0"}
  ]
end
```

## Getting Started

### Creating an Action

Actions are the basic building blocks in Jido. Here's a simple arithmetic action:

```elixir
defmodule MyApp.Actions.Add do
  use Jido.Action,
    name: "add",
    description: "Adds two numbers",
    schema: [
      value: [type: :number, required: true],
      amount: [type: :number, required: true]
    ]

  @impl true 
  def run(%{value: value, amount: amount}, _context) do
    {:ok, %{result: value + amount}}
  end
end
```

### Creating a Simple Agent

Agents combine actions into autonomous behaviors:

```elixir
defmodule MyApp.SimpleAgent do
  use Jido.Agent,
    name: "SimpleBot",
    description: "A simple agent that performs basic tasks",
    schema: [
      location: [type: :atom, default: :home],
      battery_level: [type: :integer, default: 100]
    ]

  @impl true
  def plan(%__MODULE__{} = agent) do
    {:ok, [
        {MyApp.Actions.Basic.Log, message: "Hello, world!"},
        {MyApp.Actions.Basic.Sleep, duration: 50},
        {MyApp.Actions.Basic.Log, message: "Goodbye, world!"}
     ]}
  end
end
```

### Starting an Agent Worker

Start an agent worker under your supervision tree:

```elixir
# In your application.ex
children = [
  {Registry, keys: :unique, name: Jido.AgentRegistry},
  {Jido.Agent.Supervisor, pubsub: MyApp.PubSub}
]

# Start an agent instance
{:ok, pid} = Jido.Agent.Worker.start_link(MyApp.SimpleAgent.new())
```

## Contributing

We welcome contributions! Please feel free to submit a PR.

To run tests:

```bash
mix test
```

## License

Apache License 2.0 - See [LICENSE.md](LICENSE.md) for details.