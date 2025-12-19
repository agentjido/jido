# Jido (自動)

Jido is a toolkit for building autonomous, distributed agent systems in Elixir.

The name "Jido" (自動) comes from the Japanese word meaning "automatic" or "automated", where 自 (ji) means "self" and 動 (dō) means "movement".

[![Hex Version](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/jido)
[![Mix Test](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido?branch=main)
[![Apache 2 License](https://img.shields.io/hexpm/l/jido)](https://opensource.org/licenses/Apache-2.0)

## 🚨 Important Notice

As of March 3rd, 2025, I'm working out a few final issues in prep for the v1.1 release. The `main` branch will always represent the latest release - but it may have a few quality issues that don't represent the final release. I welcome input and contributions!  You can find me in the usual Elixir community locations.

## Overview

Jido provides the foundation for building autonomous agents that can plan, execute, and adapt their behavior in distributed Elixir applications. Think of it as a toolkit for creating smart, composable workflows that can evolve and respond to their environment.

This package is geared towards Agent builders. It contains the basis building blocks for creating advanced agentic systems. This is why there's no AI baked into the core of this framework.

To see demo's and examples, check out our [Jido Workbench](https://github.com/agentjido/jido_workbench). It includes many examples of agents and workflows, including:

- Agents with Tools
- ChatBots
- Agents acting as a Team
- Multi-modal input & output
- ... and many more examples

Jido Workbench relies on the following packages to extend Jido's capabilities:

- [`jido_ai`](https://github.com/agentjido/jido_ai) package for the AI capabilities.
- [`jido_chat`](https://github.com/agentjido/jido_chat) package for the chat capabilities.
- [`jido_memory`](https://github.com/agentjido/jido_memory) package for the memory capabilities.

## Key Features

- 📦 **State Management**: Core state primitives for agents
- 🧩 **Composable Actions**: Build complex behaviors from simple, reusable actions
- 🤖 **Agent Data Structures**: Stateless agentic data structures for planning and execution
- 🔥 **Agent GenServer**: OTP integration for agents, with dynamic supervisors
- 📡 **Real-time Sensors**: Event-driven data gathering and monitoring

- 🧠 **Skills**: Reusable, composable behavior modules - Plugins for agents
- ⚡ **Distributed by Design**: Built for multi-node Elixir clusters
- 🧪 **Testing Tools**: Rich helpers for unit and property-based testing

## Installation

Add Jido to your dependencies:

```elixir
def deps do
  [
    {:jido, "~> 1.1.0"}
  ]
end
```

## Core Concepts

### Actions

Actions are the fundamental building blocks in Jido. Each Action is a discrete, reusable unit of work with a clear interface:

```elixir
defmodule MyApp.Actions.FormatUser do
  use Jido.Action,
    name: "format_user",
    description: "Formats user data by trimming whitespace and normalizing email",
    schema: [
      name: [type: :string, required: true],
      email: [type: :string, required: true]
    ]

  def run(params, _context) do
    {:ok, %{
      formatted_name: String.trim(params.name),
      email: String.downcase(params.email)
    }}
  end
end

# Execute a single Action via the Workflow system
{:ok, result} = Jido.Workflow.run(FormatUser, %{name: "John Doe", email: "john@example.com"})
```

[Learn more about Actions →](guides/actions/overview.md)

### Agents

Agents are stateful entities that can plan and execute Actions. They maintain their state through a schema and can adapt their behavior:

```elixir
defmodule MyApp.CalculatorAgent do
  use Jido.Agent,
    name: "calculator",
    description: "An adaptive calculating agent",
    actions: [
      MyApp.Actions.Add,
      MyApp.Actions.Multiply,
      Jido.Actions.Directives.RegisterAction
    ],
    schema: [
      value: [type: :float, default: 0.0],
      operations: [type: {:list, :atom}, default: []]
    ]
end

# Start the agent
{:ok, pid} = MyApp.CalculatorAgent.start_link()

# Send instructions directly to the agent
{:ok, result} = MyApp.CalculatorAgent.cmd(pid, [
  %Jido.Instruction{action: "add", params: %{a: 1, b: 2}}
])
```

[Learn more about Agents →](guides/agents/overview.md)

### Sensors

Sensors provide real-time monitoring and data gathering for your agents:

```elixir
defmodule MyApp.Sensors.OperationCounter do
  use Jido.Sensor,
    name: "operation_counter",
    description: "Tracks operation usage metrics",
    schema: [
      emit_interval: [type: :pos_integer, default: 1000]
    ]

  def mount(opts) do
    {:ok, Map.merge(opts, %{counts: %{}})}
  end

  def handle_info({:operation, name}, state) do
    new_counts = Map.update(state.counts, name, 1, & &1 + 1)
    {:noreply, %{state | counts: new_counts}}
  end
end
```

[Learn more about Sensors →](guides/sensors/overview.md)

## Running in Production

Start your agents under supervision:

```elixir
# In your application.ex
children = [
  # Agents fit into your existing supervision tree
  # Specify an id to always uniquely identify the agent
  {MyApp.CalculatorAgent, id: "calculator_1"}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Documentation

- [📘 Getting Started Guide](guides/getting-started.livemd)
- [🧩 Actions & Workflows](guides/actions/overview.md)
- [🤖 Building Agents](guides/agents/overview.md)
- [📡 Sensors & Monitoring](guides/sensors/overview.md)
- [🔄 Agent Directives](guides/agents/directives.md)

## Contributing

We welcome contributions! Here's how to get started:

1. Fork the repository
2. Run tests: `mix test`
3. Run quality checks: `mix quality`
4. Submit a PR

Please include tests for any new features or bug fixes.

See our [Contributing Guide](CONTRIBUTING.md) for detailed guidelines.

## Testing

Jido is built with a test-driven mindset and provides comprehensive testing tools for building reliable agent systems. Our testing philosophy emphasizes:

- Thorough test coverage for core functionality
- Property-based testing for complex behaviors
- Regression tests for every bug fix
- Extensive testing helpers and utilities

### Testing Utilities

Jido provides several testing helpers:

- `Jido.TestSupport` - Common testing utilities
- Property-based testing via StreamData
- Mocking support through Mimic
- PubSub testing helpers


### Running Tests

```bash
# Run the test suite
mix test

# Run with coverage reporting
mix test --cover

# Run the full quality check suite
mix quality
```

While we strive for 100% test coverage, we prioritize meaningful tests that verify behavior over simple line coverage. Every new feature and bug fix includes corresponding tests to prevent regressions.

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

## Support

- 📚 [Documentation](https://hexdocs.pm/jido)
- 💬 [GitHub Discussions](https://github.com/agentjido/jido/discussions)
- 🐛 [Issue Tracker](https://github.com/agentjido/jido/issues)
