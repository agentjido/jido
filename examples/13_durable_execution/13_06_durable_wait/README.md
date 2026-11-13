# 13_06 Durable Wait

One approval Flow releases its Runic worker while it waits. The durable Agent
can passivate. A later `Jido.Signal` reactivates the same logical Agent and
resumes the same Turn.

## What you will learn

- Use `selection`, `await`, and `timer` inside one Flow.
- Address a durable Agent with `Jido.Agent.Ref`.
- Receive `status: :waiting` and portable waits in a `TurnResult`.
- Resume the Flow by sending a matching Signal through the same Ref.

## Read the code

Read [the Agent and Flow](durable_wait.ex), then
[the behavior tests](durable_wait_test.exs).

## Run it

`mix test.examples examples/13_durable_execution/13_06_durable_wait --warnings-as-errors`

Expected result: the Agent passivates while waiting, reactivates through its
stable Ref, and completes once after approval.

## Core shape

```elixir
ref = Jido.Agent.Ref.new!(namespace: "my-app", id: "approval")
{:ok, ^ref} = Jido.create_agent(MyJido, ref, DurableWait)

{:ok, request} = DurableWait.request_signal(%{request_id: "report-1"})

{:ok, %Jido.AgentServer.TurnResult{
  status: :waiting,
  turn_id: turn_id,
  waits: [wait | _]
}} = Jido.call(MyJido, ref, request)

{:ok, approval} =
  DurableWait.resolve_signal(%{request_id: "report-1", decision: :approve})

{:ok, %Jido.AgentServer.TurnResult{status: :committed, turn_id: ^turn_id}} =
  Jido.call(MyJido, ref, approval)
```

The caller does not use a separate wait-delivery API. Normal Signal delivery
through the stable Ref matches the saved wait. A wrong request ID returns
`{:error, :wait_not_matched}`.

## Important behavior

The waiting Agent can be logically alive and passivated at the same time. The
Instance owns persistence and activation. The saved Flow keeps its Turn ID,
wait identity, and absolute deadline. Confirmed Actions do not run again.

An exact Signal retry is inert and returns the saved result. A conflicting
reuse of the same Signal ID is rejected. Only explicit deletion ends the
logical Agent lifetime.

## Limits

The example uses a file store because ETS does not survive a BEAM restart.
External Action side effects still need their own idempotency policy.

## Files

- [Agent and Flow](durable_wait.ex)
- [Behavior tests](durable_wait_test.exs)
