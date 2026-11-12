# 08_03 Failure Outcome

A Turn Outcome records where work stopped and whether state committed.

## What you will learn

- How a precommit Action failure produces an uncommitted Outcome.
- How `Jido.AgentServer.Directive.ErrorReport` reports a postcommit failure.
- How a continuing policy keeps the Agent available.
- How `:stop_on_error` stops the Agent after one failure.
- How `{:emit_signal, dispatch}` sends one bounded public error Signal.

## Read the code

Read [the failure Agent](failure_outcome.ex). Its reject Action fails before
commit. Its report Action commits state and returns a structured Error
Directive for postcommit policy handling.

## Run it

```sh
mix test.examples examples/08_runtime/08_03_failure_outcome
```

Expected result: the precommit Outcome has stage `:running` and no new state
version. The Error Directive Outcome has stage `:directive` and version one.

## Important behavior

An error policy receives the failure reason and a public summary map. The map contains status, stage, commit state,
state versions, and the Directive count. It does not contain private
Agent Server state.

The continuing policy returns `:continue`. The stopping policy uses
`:stop_on_error`. The emitted-Signal policy sends `jido.agent_server.error` to an
external dispatch target and does not emit another error Signal when that
Signal fails.

## Limits

An error policy runs after Jido knows the failure result. It cannot change a
prior commit or undo external work.

## Files

- [Source](failure_outcome.ex)
- [Tests](failure_outcome_test.exs)

Read `Server.status/1` for `last_outcome` and `last_effect_outcome`.
`Server.history/1` retains bounded Turn summaries when debug history is enabled.
A successful commit can have a later effects failure. Do not classify the
commit as failed from the effects summary.

Previous: [Turn Control](../08_02_turn_control/README.md) |
Next: [Scheduled Signals](../08_04_scheduled_signals/README.md)
