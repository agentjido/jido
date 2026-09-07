# Jido

[![Hex.pm](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido/)
[![CI](https://github.com/agentjido/jido/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido.svg)](https://github.com/agentjido/jido/blob/main/LICENSE)

Jido is a declarative actor and agent framework for Elixir. You declare what an
Agent is, instantiate that declaration as an Agent value, and run the value as
an OTP actor when you need a live process.

This `v3-spike` branch prepares `3.0.0-beta.1` for evaluation. It has breaking
changes from V2. The package is not published, and beta release checks are not
complete. See the [migration guide](guides/migration.md) for the API changes,
known limits, and required checks.

## Core model

Jido follows the declarative style common in Elixir. The declaration describes
the Agent. It does not run an imperative process loop.

1. Declare an Agent definition with its data schema, routes, Plugins, and
   metadata.
2. Instantiate the definition with an identity and initial state.
3. Route Signals to one Action or Flow.
4. Let the executable propose the next domain state and Directives.
5. Validate and commit the complete Agent value.
6. Let the Agent Server dispatch runtime effects after commit.

Direct `Jido.Agent.cmd/3` returns a candidate Agent and Directives; the Server
commits live state. Actions and Flows can perform synchronous I/O before they
return. A failed Turn preserves committed Agent state but does not undo external
work that already completed. Applications own external idempotency and recovery.
State assembly is repeatable for fixed inputs and executable results.

The Agent callback and Plugin code cannot replace private Agent Server state.

One `%Jido.Agent{}` has two valid forms. A definition has `id: nil` and
`state: nil`. An instance has a non-empty `id` and validated state. A value
that has only an id or only state is invalid.

Agent modules provide declarative `agent` and `routes` blocks, with explicit
nested `define` declarations for command and Signal helpers. Direct map and
keyword construction, module construction, the runtime Builder, and the
JSON-compatible Codec use the same Agent validation. See the
`Jido.Agent`, `Jido.Agent.Builder`, and `Jido.Agent.Codec` API documentation.

## Example

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/example"

    route "counter.increment" do
      action %{amount: amount},
        name: "increment",
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end

      defaults %{amount: 1}
      define :increment, args: [{:optional, :amount}]
    end
  end
end

agent = MyApp.Counter.new!(id: "counter-1")

signal =
  Jido.Signal.new!(
    "counter.increment",
    %{amount: 2},
    source: "/example"
  )

{:ok, candidate, []} = MyApp.Counter.cmd(agent, signal)
candidate.state.count
#=> 2
```

`cmd/2` is the main entry point for an Agent value. It routes one Signal and
returns a candidate Agent plus the Directives that a runtime can dispatch. The
original Agent value stays unchanged.

Run the same Agent value as a live actor when it needs process identity,
serialized message handling, persistence, or runtime effects:

```elixir
{:ok, _jido} = Jido.start()
{:ok, counter} = Jido.start_agent(agent)

{:ok, committed_agent} = Jido.AgentServer.call(counter, signal)
committed_agent.state.count
#=> 2
```

The default instance is also implicit for Agent lookup, listing, counts, stop,
hibernate, and thaw. Pass an instance as the first argument only when the
application runs more than one Jido supervisor.

The route `define` declaration creates helpers for the same contract. Use the
Signal helper with `cmd/2`, or use the command helper with a live actor:

```elixir
{:ok, increment_signal} = MyApp.Counter.increment_signal(3)
{:ok, candidate, []} = MyApp.Counter.cmd(agent, increment_signal)

{:ok, committed_agent} = MyApp.Counter.increment(counter, 3)
committed_agent.state.count
#=> 5
```

## Agent Plugins

A `Jido.Plugin` is one explicit Agent capability. A Plugin can admit live
Signals, prepare pure command input, transform outbound Signals, own one
portable Agent state key, reduce owned Directives, and optionally start an OTP
runtime. A Plugin that only dispatches typed Directives can omit `child_spec/1`.
The Server calls `dispatch/4` with a `nil` runtime in its supervised task.
Validation, ordering, timeout, and failure rules apply to both forms. Results
enter through the normal Agent Signal mailbox. See the `Jido.Plugin` API docs.

## Persistence

Persistence is optional. Configure one binary adapter on the Jido instance:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    persistence: {MyApp.Persistence, repo: MyApp.Repo}
end
```

All Agents in the instance inherit this adapter. A successful Agent commit is
stored before the Server reports success. `hibernate/2` saves and stops
one Server. `thaw/3` restores and starts it. Jido does not start or
supervise a persistence adapter process.

## Installation

This branch is the local `3.0.0-beta.1` candidate. It is not a published release.
For local development, point your application at this checkout:

```elixir
def deps do
  [
    {:jido, path: "../jido"}
  ]
end
```

## Guides and validation

Start with the [Getting Started Livebook](guides/getting-started.livemd), then
[build your first Agent](guides/build-your-first-agent.livemd). Read
[Actors, Agents, and Jido](guides/actor-and-agent-framework.md) for the framework
model and [Agent Definitions and Instances](guides/agent-definitions-and-instances.md)
for the value contract.

The guide set also covers [Agent Turns](guides/turns-commit-and-effects.md),
[Plugin contracts](guides/plugin-contract-and-lifecycle.md),
[actor lifecycle](guides/agent-server-lifecycle.md),
[topologies](guides/topology-definitions.md),
[persistence and recovery](guides/portable-state-and-checkpoints.md), and
[operations](guides/configuration.md). Use the
[example systems catalog](guides/example-systems.md) to find an executable
contract test. If you have V2 application code, use the
[migration guide](guides/migration.md).

[Design documents](docs/design/README.md) contain deferred proposals. They do
not define the API implemented by this branch. Cluster-exclusive ownership is
not supported.

## License

Copyright 2024-2026 Jido contributors.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
