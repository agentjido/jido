# 11_06 Durable Wait

One approval Flow releases its Runic Worker while it waits. Hibernation and
restore retain the same Turn, wait ID, and absolute deadline.

## What you will learn

- Use `selection`, `await`, and `timer` inside one Flow.
- Inspect the pending wait with `Jido.AgentServer.status/2`.
- Deliver a decision Signal without starting another Turn.
- Restore a waiting Flow without repeating completed Actions.

## Read the code

Read [the Agent and approval Flow](durable_wait.ex). The request step validates
the current Agent state. The selection accepts approval, cancellation, or a
one-hour timeout. The final step returns the complete candidate Agent state.

```elixir
alias Jido.AgentServer, as: Server
alias Jido.Examples.Durable.DurableWait

{:ok, server} = Jido.start_agent(MyJido, DurableWait,
  id: "approval", persistence: :inherit, turn_timeout: :infinity)
:ok = Server.await_ready(server)
{:ok, request} = DurableWait.request_signal(%{request_id: "report-1"})
pending = Server.submit(server, request)

# After status reports phase: :waiting:
[wait] = Server.status(server).waits
{:ok, approval} = DurableWait.resolve_signal(%{request_id: "report-1", decision: :approve})
:ok = Server.deliver_wait(server, wait.id, approval)
{:ok, approved, []} = Server.await(pending)
```

The application must configure persistence on `MyJido`. Use the same Signal ID
and wait ID if a delivery reply is lost. `:ok` confirms saved acceptance;
it does not confirm Flow completion. Delivery before the wait opens or while
the Worker runs returns `{:error, :not_waiting}`.

## Important behavior

The committed Agent stays `:idle` while the Flow waits. Other state-changing
Turns remain queued. Reads and execution cancellation remain available.
A matching decision commits `:approved` or `:cancelled`. The timer commits
`:expired` without a decision Signal. Timers win exact-time ties.

Wait input is saved before acknowledgement. The selected result is saved
before downstream work. A storage conflict or uncertain write stops the
activation. Restore reads the stored result before execution can continue.
Hibernation saves the running Turn; thaw resumes it. The original caller handle
does not survive hibernation. Use status and Agent reads after restore.

A wrong request ID is rejected. Input must address an open wait occurrence.
Duplicate equal input is inert while its receipt is retained in a pending graph.
After the Turn finishes, delivery returns `:not_waiting`. `Server.cancel/1`
cancels the Turn without committing approval state. A domain cancel Signal
completes the Flow and commits `:cancelled` instead.

## Limits

This example needs durable AgentServer execution. Ordinary Exec still rejects
waits. There is no early-input mailbox or automatic recovery scanner. The
application owns Signal delivery, authorization, storage, and clock policy.
A request needed before the wait cannot be a deferred post-commit Directive.
Wait input and resolution counts are bounded; this is not graph compaction.
Map and Iterate Flow bodies remain unsupported. The Turn deadline also remains
in force; this lesson uses `turn_timeout: :infinity` so the Flow timer owns expiry.

The [tests](../../../test/examples/11_durable/11_06_durable_wait/durable_wait_test.exs)
prove approval and cancellation, hibernation, unchanged wait identity and deadline,
timer expiry, completed expiry after thaw, and process cleanup. The expiry
test reuses the same request and finish Actions with a zero-duration Selection.
Core tests retain storage fault and clock edge cases. The
example does not prove power-loss or storage-loss recovery.

## Run it

```sh
mix test test/examples/11_durable/11_06_durable_wait --include example --seed 0 --warnings-as-errors
```

Expected result: all behavior tests pass. No external service is required.

## Files

- [Source](durable_wait.ex)
- [Tests](../../../test/examples/11_durable/11_06_durable_wait/durable_wait_test.exs)
- [Integration boundary](../proposals/flow-control/INTEGRATION.md)

Previous: [Saved Completion](../11_05_saved_completion/README.md) | Next: [External Uncertainty](../11_07_external_uncertainty/README.md)
