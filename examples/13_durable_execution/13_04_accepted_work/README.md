# 13_04 Accepted Work

A member in a declared static topology runs one Flow as a durable Agent Turn.

## What you will learn

- A Flow Signal is accepted before its first Action runs.
- A successful call returns a committed `TurnResult`.
- Agent state is read from `Jido.AgentServer.snapshot/2`.
- Worker recovery restores the saved member state without another Turn.

## Read the code

Read [the Agent and Flow](accepted_work.ex), then
[the tests](accepted_work_test.exs).

## Core result

```elixir
{:ok, request} =
  Jido.Examples.Durable.AcceptedWork.request_signal(%{topic: "OTP"})

{:ok, %Jido.AgentServer.TurnResult{status: :committed} = result} =
  Jido.AgentServer.call(member_server, request)

snapshot = Jido.AgentServer.snapshot(member_server)
snapshot.agent.state # %{report: "Report: OTP"}
result.agent_address.id == snapshot.agent.id
```

## Important behavior

The topology member handle in the behavior test comes from test-only OTP
inspection. It is not a public AgentServer member API. Application code should
address independent durable Agents with stable `Jido.Agent.Address` values.

## Run it

```sh
mix test.examples examples/13_durable_execution/13_04_accepted_work --warnings-as-errors
```

## Limits

Repeated Signals start new Turns. Static topology does not create an atomic
family save. External effects still need idempotency.

## Files

- [Source](accepted_work.ex)
- [Tests](accepted_work_test.exs)
