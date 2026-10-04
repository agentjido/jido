# 04_16 Turn Control

Public status data identifies active work for precise precommit cancellation.

## What you will learn

- How `AgentServer.status/2` exposes a stable active Turn ID.
- How `cancel_turn/3` cancels only the matching active Turn.
- How a stale Turn ID fails without changing active work.
- Why precommit cancellation keeps the last committed snapshot.

## Read the code

Read [the example Agent](turn_control.ex). Then read the behavior test. The test
uses a fixed support barrier to hold the Action before commit. The barrier does
not enter Signal data, Action input, or Turn context.

## Run it

```sh
mix test test/examples/04_runtime/04_16_turn_control --include example --seed 0
```

Expected result: status reports the active Turn. A stale ID is rejected. The
matching cancellation returns `:ok`, and the snapshot stays at revision zero.

## Important behavior

Use the Turn ID from the public `status/2` map when cancellation must not affect
later work. The active summary is `nil` when no Turn is active.

Cancellation can stop eligible admission or Action work before commit. It does
not undo completed Action I/O, reverse a completed commit, or reverse an
external Directive that already ran.

## Limits

Cancellation is not a transaction for external systems. An application must
make external operations idempotent when a retry is possible.

## Files

- [Source](turn_control.ex)
- [Tests](../../../test/examples/04_runtime/04_16_turn_control/turn_control_test.exs)

Previous: [Request Modes](../04_15_request_modes/README.md) | Next: [Failure Outcome](../04_17_failure_outcome/README.md)
