# Minimal Agent

A small Agent keeps a counter and changes it through one typed Signal route.

## What you will learn

- How to declare Agent state and an inline Action.
- How route defaults and generated command helpers work.
- How direct and live execution use the same Agent contract.

## Read the code

Read [the Agent](minimal_agent.ex) first. Then read
[the behavior tests](../../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs).

## Run it

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs --include example --seed 0
```

Expected result: the tests complete without failures. They show default and
explicit increments, unchanged state after invalid input, and separate state
for two Agent instances.

## Important behavior

Start an instance with `state:` and wait for readiness before using it:

```elixir
alias Jido.AgentServer, as: Server
alias Jido.Examples.MinimalAgent

{:ok, server} = Jido.start_agent(MyJido, MinimalAgent, id: "counter", state: %{count: 4})
:ok = Server.await_ready(server)
{:ok, signal} = MinimalAgent.increment_signal(%{amount: 3})
{:ok, agent, []} = Server.call(server, signal)
agent.state # %{count: 7}
```

An invalid amount does not change committed state. A later valid command can
still commit. Direct execution does not change the live Agent Server.

## Limits

This example does not teach Plugins, Directives, persistence, or concurrent
Turns.

## Files

- [Agent source](minimal_agent.ex)
- [Behavior tests](../../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs)

Previous: [Basic overview](../README.md) | Next: [Typed Command Agent](../01_02_typed_command_agent/README.md)
