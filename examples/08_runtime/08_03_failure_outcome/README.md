# 08_03 Failure Outcome

An accepted Turn failure is data. It does not crash the caller or replace the
committed Agent state.

## What you will learn

- `AgentServer.call/3` returns a `TurnResult` for accepted work.
- A failed accepted Turn has `status: :failed` and carries its error.
- A failed Turn does not change the `Snapshot`.
- The same Agent can commit a later Turn.

## Read the code

Read [the failure Agent](failure_outcome.ex). Its reject Action returns an
execution error. Its accept Action updates Agent state.

## Run it

```sh
mix test.examples examples/08_runtime/08_03_failure_outcome
```

The test first saves the committed `Snapshot`. It then checks the failed
`TurnResult`, confirms that the snapshot is unchanged, and commits valid work.

## Files

- [Source](failure_outcome.ex)
- [Tests](failure_outcome_test.exs)

Previous: [Turn Control](../08_02_turn_control/README.md) |
Next: [Scheduled Signals](../08_04_scheduled_signals/README.md)
