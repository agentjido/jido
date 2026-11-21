# 03_05 Map

Map applies one Action to an ordered collection with bounded concurrency.

## What you will learn

- How one Action receives every item.
- How item failures can be collected as data.

## Read the code

Read [the Map Flow](map.ex), then [the test](map_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_05_map --warnings-as-errors`

Expected result: outputs keep input order and the configured failure mode is
explicit.

## Important behavior

The complete Map compiles to one execution node with an explicit concurrency
bound.

## Limits

This lesson does not stream unbounded input or persist per-item progress.

## Files

- [Map Flow](map.ex)
- [Tests](map_test.exs)

[Previous: Parallel](../03_04_parallel/README.md) |
[Next: Reduce](../03_06_reduce/README.md)
