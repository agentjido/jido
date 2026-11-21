# 03_10 Handoff

Handoff returns one successor Instruction and stops the current Flow.

## What you will learn

- How a Flow selects a validated successor.
- Where ownership passes back to the caller.

## Read the code

Read [the Handoff Flow](handoff.ex), then [the test](handoff_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_10_handoff --warnings-as-errors`

Expected result: execution returns the successor Instruction without running
it inside the current Flow.

## Important behavior

The caller decides when and where to run the successor.

## Limits

Handoff does not transfer process ownership or guarantee remote delivery.

## Files

- [Handoff Flow](handoff.ex)
- [Tests](handoff_test.exs)

[Previous: Invoke](../03_09_invoke/README.md) |
[Next: Effects and Failure](../03_11_effects_and_failure/README.md)
