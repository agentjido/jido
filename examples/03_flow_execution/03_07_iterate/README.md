# 03_07 Iterate

Iterate replaces loop state until its condition is false or its bound is
reached.

## What you will learn

- How loop state moves between iterations.
- How an explicit maximum prevents an unbounded loop.

## Read the code

Read [the Iterate Flow](iterate.ex), then [the test](iterate_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_07_iterate --warnings-as-errors`

Expected result: normal input completes at the condition, and bounded input
stops at the declared maximum.

## Important behavior

The complete Iterate block compiles to one execution node.

## Limits

The maximum is a run bound, not a durable retry policy.

## Files

- [Iterate Flow](iterate.ex)
- [Tests](iterate_test.exs)

[Previous: Reduce](../03_06_reduce/README.md) |
[Next: Subflow](../03_08_subflow/README.md)
