# Jido

[![Hex.pm](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido/)
[![CI](https://github.com/agentjido/jido/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido.svg)](https://github.com/agentjido/jido/blob/main/LICENSE)

Jido is an Agent framework for Elixir. It keeps domain state in immutable
`%Jido.Agent{}` values and puts OTP runtime state in `Jido.AgentServer`.

## Core model

1. Define neutral Agent data and its Zoi state schema.
2. Instantiate the definition with an identity and state.
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

Agent modules also support the Spark `agent` and `routes` blocks, with explicit
nested `define` declarations for command and Signal helpers. Direct map and
keyword construction, module construction, the runtime Builder, and the
JSON-compatible Codec use the same Agent validation. See the
`Jido.Agent`, `Jido.Agent.Builder`, and `Jido.Agent.Codec` API documentation.

## Example

```elixir
defmodule MyApp.Increment do
  use Jido.Action,
    name: "increment",
    schema: Zoi.object(%{amount: Zoi.integer()})

  @impl Jido.Action
  def run(%{amount: amount}, context) do
    {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
  end
end

defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/example"

    route "counter.increment", MyApp.Increment do
      defaults %{amount: 1}
      define :increment, args: [{:optional, :amount}]
    end
  end
end

definition = MyApp.Counter.agent()
#=> %Jido.Agent{id: nil, state: nil, ...}

instance = MyApp.Counter.new!(id: "counter-1")
#=> %Jido.Agent{id: "counter-1", state: %{count: 0}, ...}

{:ok, _jido} = Jido.start()
{:ok, counter} = Jido.start_agent(Jido.default_instance(), MyApp.Counter, id: "counter-1")

{:ok, signal} = MyApp.Counter.increment_signal(2)
{:ok, _candidate, []} = MyApp.Counter.cmd(instance, signal)
{:ok, agent} = MyApp.Counter.increment(counter, 2)
agent.state.count
#=> 2
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

Add `jido` to your dependencies:

```elixir
def deps do
  [
    {:jido, "~> 3.0"}
  ]
end
```

## License

Copyright 2024-2026 Jido contributors.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
