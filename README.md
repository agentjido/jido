# Jido

[![Hex.pm](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido/)
[![CI](https://github.com/agentjido/jido/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido.svg)](https://github.com/agentjido/jido/blob/main/LICENSE)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido?branch=main)

> **Pure functional agents and OTP runtime for building autonomous multi-agent workflows in Elixir.**

_The name "Jido" (自動) comes from the Japanese word meaning "automatic" or "automated", where 自 (ji) means "self" and 動 (dō) means "movement"._

_Learn more about Jido at [agentjido.xyz](https://agentjido.xyz)._

## Overview

With Jido, your agents are immutable data structures with a single command function:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    description: "My custom agent",
    schema: [
      count: [type: :integer, default: 0]
    ]
  end
end

{agent, directives} = MyAgent.cmd(agent, action)
```

State changes are pure data transformations; side effects are described as directives and executed by an OTP runtime. You get deterministic agent logic, testability without processes, and a clear path to running those agents in production.

## The Jido Ecosystem

Jido is the core package of the Jido ecosystem. The ecosystem is built around the core Jido Agent behavior and offer several opt-in packages to extend the core behavior.

| Package                                                 | Description                                                                                   |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [req_llm](https://github.com/agentjido/req_llm)         | HTTP client for LLM APIs                                                                      |
| [jido_action](https://github.com/agentjido/jido_action) | Composable, validated actions with AI tool integration                                        |
| [jido_signal](https://github.com/agentjido/jido_signal) | CloudEvents-based message envelope and supporting utilities for routing and pub/sub messaging |
| [jido](https://github.com/agentjido/jido)               | Core agent framework with state management, directives, and runtime                           |
| [jido_ai](https://github.com/agentjido/jido_ai)         | AI/LLM integration for agents                                                                 |

For demos and examples of what you can build with the Jido Ecosystem, see [https://agentjido.xyz](https://agentjido.xyz).

## Why Jido?

OTP primitives are excellent. You can build agent systems with raw GenServer. But when building *multiple cooperating agents*, you'll reinvent:

| Raw OTP                             | Jido Formalizes                         |
| ----------------------------------- | --------------------------------------- |
| Ad-hoc message shapes per GenServer | Signals as standard envelope            |
| Business logic mixed in callbacks   | Actions as reusable command pattern     |
| Implicit effects scattered in code  | Directives as typed effect descriptions |
| Custom child tracking per server    | Built-in parent/child hierarchy         |
| Process exit = completion           | State-based completion semantics        |

Jido isn't "better GenServer" - it's a formalized agent pattern built *on* GenServer.

## Key Features

### Immutable Agent Architecture
- Pure functional agent design inspired by Elm/Redux
- `cmd/2` as the core operation: actions in, updated agent + directives out
- Schema-validated state with NimbleOptions or Zoi

### Directive-Based Effects
- Actions transform state; directives describe external effects
- Built-in directives: Emit, Spawn, SpawnAgent, StopChild, Schedule, Stop
- Protocol-based extensibility for custom directives

### OTP Runtime Integration
- GenServer-based AgentServer for production deployment
- Parent-child agent hierarchies with lifecycle management
- Signal routing with configurable strategies
- Instance-scoped supervision for multi-tenant deployments

### Composable Plugins
- Reusable capability modules that extend agents
- State isolation per plugin with automatic schema merging
- Lifecycle hooks for initialization and signal handling

### Execution Strategies
- Direct execution for simple workflows
- FSM (Finite State Machine) strategy for state-driven workflows
- Extensible strategy protocol for custom execution patterns

### Multi-Agent Orchestration
- Multi-agent workflows with configurable strategies
- Plan-based orchestration for complex workflows
- Extensible strategy protocol for custom execution patterns

## Installation

### Using Igniter (Recommended)

The fastest way to get started is with [Igniter](https://hex.pm/packages/igniter):

```bash
mix igniter.install jido
```

This automatically:
- Adds Jido to your dependencies
- Creates configuration in `config/config.exs`
- Adds `Jido.Bus.InMemory` to your supervision tree

Generate an example agent to get started:

```bash
mix igniter.install jido --example
```

### Manual Installation

Add `jido` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 2.0"}
  ]
end
```

Then define a Jido instance module and add it to your supervision tree:

```elixir
# In lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

```elixir
# In config/config.exs
config :my_app, MyApp.Jido,
  max_tasks: 1000,
  agent_pools: []
```

```elixir
# In your application.ex
children = [
  MyApp.Jido
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Quick Start

### 1. Define an Agent

```elixir
defmodule MyApp.CounterAgent do
  use Jido.Agent,
    name: "counter",
    description: "A simple counter agent",
    schema: [
      count: [type: :integer, default: 0]
    ]
end
```

### 2. Define an Action

```elixir
defmodule MyApp.Actions.Increment do
  use Jido.Action,
    name: "increment",
    description: "Increments the counter by a given amount",
    schema: [
      amount: [type: :integer, default: 1]
    ]

  def run(params, context) do
    current = context.state[:count] || 0
    {:ok, %{count: current + params.amount}}
  end
end
```

### 3. Execute Commands

```elixir
# Create an agent
agent = MyApp.CounterAgent.new()

# Execute an action - returns updated agent + directives
{agent, directives} = MyApp.CounterAgent.cmd(agent, {MyApp.Actions.Increment, %{amount: 5}})

# Check the state
agent.state.count
# => 5
```

### 4. Run with AgentServer

```elixir
# Start the agent server
{:ok, pid} = MyApp.Jido.start_agent(MyApp.CounterAgent, id: "counter-1")

# Send signals to the running agent (synchronous)
{:ok, agent} = Jido.AgentServer.call(pid, Jido.Signal.new!("increment", %{amount: 10}, source: "/user"))

# Look up the agent by ID
pid = MyApp.Jido.whereis("counter-1")

# List all running agents
agents = MyApp.Jido.list_agents()
```

## Core Concepts

### The `cmd/2` Contract

The fundamental operation in Jido:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

Key invariants:
- The returned `agent` is always complete - no "apply directives" step needed
- `directives` describe external effects only - they never modify agent state
- `cmd/2` is a pure function - same inputs always produce same outputs

### Actions vs Directives vs State Operations

| Actions                                    | Directives                            | State Operations                |
| ------------------------------------------ | ------------------------------------- | ------------------------------- |
| Transform state, may perform side effects  | Describe external effects             | Describe internal state changes |
| Executed by `cmd/2`, update `agent.state`  | Bare structs emitted by agents        | Applied by strategy layer       |
| Can call APIs, read files, query databases | Runtime (AgentServer) interprets them | Never leave the strategy        |

### State Operations (`Jido.Agent.StateOp`)

State operations are internal state transitions handled by the strategy layer during `cmd/2`. Unlike directives, they never reach the runtime.

| StateOp        | Purpose                          |
| -------------- | -------------------------------- |
| `SetState`     | Deep merge attributes into state |
| `ReplaceState` | Replace state wholesale          |
| `DeleteKeys`   | Remove top-level keys            |
| `SetPath`      | Set value at nested path         |
| `DeletePath`   | Delete value at nested path      |

### Directive Types

| Directive    | Purpose                                          |
| ------------ | ------------------------------------------------ |
| `Emit`       | Dispatch a signal via configured adapters        |
| `Error`      | Signal an error from cmd/2                       |
| `Spawn`      | Spawn a generic BEAM child process               |
| `SpawnAgent` | Spawn a child Jido agent with hierarchy tracking |
| `StopChild`  | Gracefully stop a tracked child agent            |
| `Schedule`   | Schedule a delayed message                       |
| `Stop`       | Stop the agent process                           |

## Documentation

**Start here:**
- [Quick Start](guides/getting-started.livemd) - Build your first agent in 5 minutes
- [Core Loop](guides/core-loop.md) - Understand the mental model

**Guides:**
- [Building Agents](guides/agents.md) - Agent definitions and state management
- [Signals & Routing](guides/signals.md) - Signal-based communication
- [Agent Directives](guides/directives.md) - Effect descriptions for the runtime
- [Runtime and AgentServer](guides/runtime.md) - Process-based agent execution
- [Persistence & Storage](guides/storage.md) - Hibernate, thaw, and InstanceManager lifecycle
- [Plugins](guides/plugins.md) - Composable capability bundles
- [Strategies](guides/strategies.md) - Execution strategies (Direct, FSM)

**Advanced:**
- [FSM Strategy Deep Dive](guides/fsm-strategy.livemd) - State machine workflows
- [Worker Pools](guides/worker-pools.md) - Pre-warmed agent pools for throughput
- [Testing Agents](guides/testing.md) - Testing patterns and best practices

**API Reference:** [hexdocs.pm/jido](https://hexdocs.pm/jido)

## Development

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 26+

### Running Tests

```bash
mix test
```

### Quality Checks

```bash
mix quality  # Runs formatter, dialyzer, and credo
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Setting up your development environment
- Running tests and quality checks
- Submitting pull requests
- Code style guidelines

## License

Copyright 2024-2025 Mike Hostetler

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Links

- **Documentation**: [https://hexdocs.pm/jido](https://hexdocs.pm/jido)
- **GitHub**: [https://github.com/agentjido/jido](https://github.com/agentjido/jido)
- **AgentJido**: [https://agentjido.xyz](https://agentjido.xyz)
- **Jido Workbench**: [https://github.com/agentjido/jido_workbench](https://github.com/agentjido/jido_workbench)
