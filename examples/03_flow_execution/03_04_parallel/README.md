# 03_04 Parallel

Parallel Actions run with a concurrency bound and return results in declaration
order.

## What you will learn

- How to set a bound on concurrent work.
- How ordered join results stay deterministic.

## Read the code

Read [the Parallel Flow](parallel.ex), then [the test](parallel_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_04_parallel --warnings-as-errors`

Expected result: work can overlap, but the returned list follows declaration
order.

## Important behavior

The complete Parallel block compiles to one execution node.

## Limits

This lesson does not persist partial branch progress.

## Files

- [Parallel Flow](parallel.ex)
- [Tests](parallel_test.exs)

[Previous: Choice](../03_03_choice/README.md) |
[Next: Map](../03_05_map/README.md)
