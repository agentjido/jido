# Jido

[![Hex.pm](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido/)
[![CI](https://github.com/agentjido/jido/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido.svg)](https://github.com/agentjido/jido/blob/main/LICENSE)

Build validated, supervised agents for Elixir: declare an Agent's state and
routes once, test it as plain data, and run it as an OTP process that commits
state before it performs side effects.

```elixir
signal = MyApp.Counter.increment_signal!(%{amount: 2})

# Plain data: no process, nothing saved, nothing sent
{:ok, candidate, []} = MyApp.Counter.cmd(agent, signal)

# Live process: one Turn at a time, committed before effects run
{:ok, counter} = Jido.start_agent(agent)
{:ok, committed, []} = Jido.AgentServer.call(counter, signal)
```

Version `3.0.0-beta.2` is an evaluation candidate with breaking changes from
V2 and beta.1. The
[release record](https://github.com/agentjido/jido/blob/release/v3/docs/release-beta.2.md)
lists its checks and known limits.

## Where This Package Fits

Jido is the core runtime of the Jido ecosystem. It owns Agents, the Agent
Server, Plugins, state transitions, and Directives. Other packages build on
it. See [jido.run](https://jido.run) for the ecosystem overview and
cross-package tutorials.

**Works best with:**

- [jido_action](https://hex.pm/packages/jido_action) – the Actions and Flows
  that Agent routes run. Installed with Jido.
- [jido_signal](https://hex.pm/packages/jido_signal) – the Signal envelope,
  routing, dispatch, and bus. Installed with Jido.
- [jido_ai](https://hex.pm/packages/jido_ai) – model calls, tool use, and AI
  agent behavior on top of Jido Agents.

## Installation

```elixir
def deps do
  [
    {:jido, "~> 3.0.0-beta.2"}
  ]
end
```

Jido requires Elixir 1.18 and OTP 27 or later.

## Quick Start

Declare an Agent with a state schema and one route:

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  agent do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app")

    route "counter.increment", as: :increment, defaults: %{amount: 1} do
      action %{amount: amount},
        name: "increment",
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
end
```

Create an instance and apply a Signal to it as data:

```elixir
agent = MyApp.Counter.instantiate!(id: "counter-1")
signal = MyApp.Counter.increment_signal!(%{amount: 2})

{:ok, candidate, []} = MyApp.Counter.cmd(agent, signal)
candidate.state.count
# => 2
```

`cmd/2` returns a candidate Agent and a list of Directives. `agent` is
unchanged. No process starts and nothing is saved.

Run the same value as a live process:

```elixir
{:ok, _jido} = Jido.start()
{:ok, counter} = Jido.start_agent(agent)

{:ok, committed, []} = Jido.AgentServer.call(counter, signal)
committed.state.count
# => 2
```

`call/3` returns `{:ok, committed_agent, directives}` after the Server commits
the new state. The reply confirms the commit. Directives run after it.

`as: :increment` generated `increment_signal!/2`, which returns the Signal or
raises when the data isn't a plain map or an option is invalid.
`increment_signal/2` returns `{:ok, signal}` or `{:error, reason}` instead.
Neither checks the data against the Action schema; the Turn does that. `defaults:` fills `amount` when the Signal data
leaves it out.

## Why This Library?

- **State is validated on every change.** An Action returns the complete next
  state. Jido checks it against the schema, including Plugin-owned fields,
  before commit. A failed Turn leaves the committed state unchanged.
- **Side effects wait for the commit.** Actions return Directives as data. The
  Agent Server runs them only after the state is committed, so a failed Turn
  sends no Signals and starts no processes.
- **The same Agent runs with or without a process.** Unit-test routes with
  `cmd/2` and no setup. Run the identical value in an Agent Server in
  production.
- **It is standard OTP.** Each live Agent is a `:gen_statem` under a
  supervisor, addressed through a Registry. No custom scheduler.

Jido doesn't undo external I/O. An Action that calls an HTTP API before a
failed validation has still made that call. Make such calls idempotent, or
return them as Directives.

## Documentation

Full documentation is on [HexDocs](https://hexdocs.pm/jido). Start with:

- [Getting Started](guides/getting-started.livemd) – build and run a counter
  Agent in Livebook.
- [OTP Concepts](guides/otp-concepts-for-jido.md) – the processes,
  supervisors, and timeouts behind a live Agent.
- [Life of a Signal](guides/signal-to-effects.md) – each stage of a Turn,
  from admission to effects.
- [Pure or Live Execution](guides/pure-or-live-execution.md) – when to use
  `cmd/2` and when to start an Agent Server.

## Features

- Agent definitions from the `agent`/`routes` DSL, plain maps with
  `Jido.Agent.define/1`, or JSON through `Jido.Agent.Codec`. All three run the
  same validation.
- Routes to Actions, Flows, transforms, and pass-through handlers, matched in
  declaration order with exact types or `*` wildcards.
- Generated Signal constructors from `as:` and typed Signals with
  `Jido.SignalAction`.
- Built-in Directives to emit Signals, send to other Agents, start and stop
  Agents and processes, and stop the Server.
- Nested Agents with counts and state bindings, connected by declared
  Signal routes.
- Plugins that prepare input, own a state field, supervise runtime resources,
  and handle their own Directives.
- Built-in Plugins for Signal buses, audit records, heartbeats and schedules,
  and managed sensors.
- Optional persistence with ETS, File, Mnesia, Ecto, Redis, S3, and Bedrock
  adapters, hibernate and thaw, and revision checks.
- Telemetry under `[:jido, :agent_server]`, Turn status, and bounded Turn
  history.

## Examples

### Test a route without a process

```elixir
test "increment adds the amount" do
  agent = MyApp.Counter.instantiate!(id: "test")
  signal = MyApp.Counter.increment_signal!(%{amount: 3})

  assert {:ok, %{state: %{count: 3}}, []} = MyApp.Counter.cmd(agent, signal)
end
```

### Emit a Signal after commit

An Action returns an `emit/2` Directive. The Server sends it after the commit,
here to the calling process:

```elixir
defmodule MyApp.Reset do
  use Jido.Action, name: "reset", schema: Zoi.object(%{})

  @impl true
  def run(_params, %{agent_state: state}) do
    {:ok, %{state | count: 0},
     [Jido.Agent.Directive.emit("counter.cleared", %{previous: state.count})]}
  end
end

# In the Agent: route "counter.reset", MyApp.Reset, as: :reset

{:ok, counter} =
  Jido.start_agent(MyApp.Counter, id: "counter-2", default_dispatch: {:pid, target: self()})
reset = MyApp.Counter.reset_signal!()
{:ok, _committed, [_emit]} = Jido.AgentServer.call(counter, reset)

receive do
  {:signal, %Jido.Signal{type: "counter.cleared", data: data}} -> data
end
# => %{previous: 0}
```

### Persist every commit

Add an adapter and a stable namespace to your Jido instance:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/agents",
    persistence: {Jido.Persistence.Ecto, repo: MyApp.Repo}
end
```

Persistence is off by default. Opt in when you start an Agent:

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyApp.Counter, id: "counter-1", persistence: :inherit)
```

That Agent saves each commit before the Server replies. `hibernate/2` saves and
stops it, and `thaw/3` restores it. Jido doesn't start or supervise your Repo.

## License

Copyright 2024-2026 Jido contributors.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
