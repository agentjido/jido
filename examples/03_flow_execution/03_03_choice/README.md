# 03_03 Choice

An ordered Choice runs the first matching branch or its fallback.

## What you will learn

- How safe expressions select a branch in order.
- How the complete Choice compiles to one execution node.

## Read the code

Read [the Choice Flow](choice.ex), then [the test](choice_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_03_choice --warnings-as-errors`

Expected result: matching input selects the first valid branch, and unmatched
input uses the fallback.

## Important behavior

Only the selected branch runs.

## Limits

This lesson does not retry a failed branch or select several branches.

## Files

- [Choice Flow](choice.ex)
- [Tests](choice_test.exs)

[Previous: Steps and References](../03_02_steps_and_references/README.md) |
[Next: Parallel](../03_04_parallel/README.md)
