# 04_17 Failure Outcome

A Turn Outcome records where work stopped and whether state committed.

## What you will learn

- How a precommit Action failure produces an uncommitted Outcome.
- How `Jido.Agent.Directive.Error` reports a postcommit failure.
- How a continuing policy keeps the Agent available.
- How `:stop_on_error` stops the Agent after one failure.
- How `{:emit_signal, dispatch}` sends one bounded public error Signal.

## Read the code

Read [the failure Agent](failure_outcome.ex). Its reject Action fails before
commit. Its report Action commits state and returns a structured Error
Directive for postcommit policy handling.

## Run it

```sh
mix test test/examples/04_runtime/04_17_failure_outcome --include example --seed 0
```

Expected result: the precommit Outcome has stage `:execute` and no new state
version. The Error Directive Outcome has stage `:directive` and version one.

## Important behavior

An error policy receives the failure reason and the public
`Jido.Agent.Turn.Outcome`. The Outcome contains status, stage, commit state,
state versions, and a bounded Directive summary. It does not contain private
Agent Server state.

The continuing policy returns `:continue`. The stopping policy uses
`:stop_on_error`. The emitted-Signal policy sends `jido.agent.error` to an
external dispatch target and does not emit another error Signal when that
Signal fails.

## Limits

An error policy runs after Jido knows the failure result. It cannot change a
prior commit or undo external work.

## Files

- [Source](failure_outcome.ex)
- [Tests](../../../test/examples/04_runtime/04_17_failure_outcome/failure_outcome_test.exs)

Previous: [Turn Control](../04_16_turn_control/README.md) | Next: [Heartbeat](../04_18_heartbeat/README.md)
