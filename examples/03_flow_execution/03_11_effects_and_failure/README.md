# 03_11 Effects and Failure

Flow execution returns successful effects as data and reports a failed
component without dispatching effects.

## What you will learn

- How successful component effects keep authored order.
- How Flow failure separates evaluation from effect dispatch.

## Read the code

Read [the Flow](effects_and_failure.ex), then
[the test](effects_and_failure_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_11_effects_and_failure --warnings-as-errors`

Expected result: successful effects are ordered, and failed work returns an
error without exposing its effects.

## Important behavior

`Jido.Exec` returns effects. It does not dispatch them.

## Limits

Commit-before-effects and dispatch failure belong to AgentServer lessons.

## Files

- [Flow](effects_and_failure.ex)
- [Tests](effects_and_failure_test.exs)

[Previous: Handoff](../03_10_handoff/README.md) |
[Next: Wait and Signal](../03_12_wait_and_signal/README.md)
