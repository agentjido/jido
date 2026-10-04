# 04_15 Request Modes

Agent Server request modes provide different reply and delivery contracts.

## What you will learn

- How `call/3` waits for one commit and returns `{:ok, agent}`.
- How `cast/2` returns `:ok` before best-effort delivery completes.
- How `send_request/3` separates sending from `receive_response/2`.
- Why a caller timeout does not cancel work that already started.

## Read the code

Read [the recording Agent](request_modes.ex). Then read the behavior test for
the request results, serial commit order, and timeout boundary.

## Run it

```sh
mix test test/examples/04_runtime/04_15_request_modes --include example --seed 0
```

Expected result: the three request modes commit in arrival order. A caller can
stop waiting while the active work still commits.

## Important behavior

One Agent Server accepts Turns in serial order. `call/3` returns a direct
success or error. `send_request/3` returns a request identifier, and
`receive_response/2` returns the OTP response envelope.

The default postponed-Signal limit is 1,000. Calls and asynchronous requests
return an overload error when Jido can reject admission. A cast always returns
`:ok`, but Jido can drop it under overload. The limit covers work that the
state machine received and postponed. It does not limit its complete mailbox.

## Limits

Request modes do not add parallel Turn execution inside one Agent. Use
explicit cancellation when a caller timeout must stop eligible active work.

## Files

- [Source](request_modes.ex)
- [Tests](../../../test/examples/04_runtime/04_15_request_modes/request_modes_test.exs)

Previous: [State Migration](../04_14_state_migration/README.md) | Next: [Turn Control](../04_16_turn_control/README.md)
