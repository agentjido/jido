# 03_06 Reduce

Reduce updates one accumulator in collection order.

## What you will learn

- How each item receives the current accumulator.
- Why Reduce runs its Action serially.

## Read the code

Read [the Reduce Flow](reduce.ex), then [the test](reduce_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_06_reduce --warnings-as-errors`

Expected result: the final value reflects every item in order.

## Important behavior

The complete Reduce compiles to one execution node.

## Limits

This lesson does not parallelize accumulator updates.

## Files

- [Reduce Flow](reduce.ex)
- [Tests](reduce_test.exs)

[Previous: Map](../03_05_map/README.md) |
[Next: Iterate](../03_07_iterate/README.md)
