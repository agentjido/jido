# Parallel Join

A Flow declares two independent branches and joins their named results into one
Agent state candidate.

## What you will learn

- How independent steps form parallel-ready work.
- How result references make the join wait for both branches.
- How one branch failure prevents the joined candidate from committing.

## Read the code

Read [the Agent and Flow](parallel_join.ex) first. Then read
[the behavior tests](parallel_join_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_20_parallel_join --warnings-as-errors
```

Expected result: both branch results reach the join, shared context reaches
each branch, and a branch failure preserves prior state.

## Important behavior

The Flow graph permits the `left` and `right` steps to run concurrently. The
executor's `max_concurrency` option sets the runtime limit. `Fetch` is named
because both branches reuse it; the one-use join stays inline.

## Limits

The tests prove joined output and failure behavior. Detailed scheduler timing
and cancellation belong to Jido Flow and Agent Server core tests.

## Files

- [Source](parallel_join.ex)
- [Tests](parallel_join_test.exs)

Previous: [Choice and Fallback](../03_19_conditional_routes/README.md) | Next: [Ordered Batch](../03_21_ordered_batch/README.md)
