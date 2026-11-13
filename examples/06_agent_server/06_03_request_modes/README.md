# 06_03 Request Modes

Agent Server request modes provide different reply and delivery contracts.

## What you will learn

- How `call/3` waits for one accepted Turn and returns a `TurnResult`.
- How `cast/2` returns `:ok` before best-effort delivery completes.
- How `submit/3` separates sending from `await/2`.
- Why a caller timeout does not cancel work that already started.

## Read the code

Read [the recording Agent](request_modes.ex). Then read the behavior test for
the request results, serial commit order, and timeout boundary.

## Run it

```sh
mix test.examples examples/06_agent_server/06_03_request_modes
```

Expected result: the three request modes commit in arrival order. A caller can
stop waiting while the active work still commits.

## Important behavior

One Agent Server accepts Turns in serial order. `call/3` returns a `TurnResult`
for accepted work. `submit/3` returns a Pending handle. The same caller uses
`await/2` to collect that result.

The default postponed-Signal limit is 1,000. Calls and asynchronous requests
return an overload error when Jido can reject admission. A cast always returns
`:ok`, but Jido can drop it under overload. The limit covers work that the
state machine received and postponed. It does not limit its complete mailbox.

## Limits

Request modes do not add parallel Turn execution inside one Agent. Use
explicit cancellation when a caller timeout must stop eligible active work.

## Files

- [Source](request_modes.ex)
- [Tests](request_modes_test.exs)

```elixir
{:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
  Jido.AgentServer.call(server, signal)
:ok = Jido.AgentServer.cast(server, signal)
pending = Jido.AgentServer.submit(server, signal)
{:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
  Jido.AgentServer.await(pending)
```

Accepted failures are `TurnResult` values with `status: :failed`. Admission and
transport errors return `{:error, reason}`. A caller wait timeout does not
cancel accepted or queued work. Cast returns before the work commits.

Previous: [Start and Address](../06_01_start_and_address/README.md) |
Next: [Turn Control](../08_02_turn_control/README.md)

The tests also prove overload with one queued slot, cast drop under overload,
and an expired admission deadline. `await(pending, 0)` can time out while the
same owner can await again. `abandon/1` drops reply tracking; active work still
commits. Pending handles belong to the submitting process. Admission timeout
limits when work can start; caller timeout limits how long the caller waits.
