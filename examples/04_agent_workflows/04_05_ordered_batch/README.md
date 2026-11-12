# Ordered Batch

Map processes a collection while Reduce builds one ordered Agent result.

## What you will learn

- How Map keeps results in input order.
- How collected and fail-fast error policies differ.
- How Reduce consumes successful Map output and handles an empty collection.

## Read the code

Read [the Agent and two Flows](ordered_batch.ex) first. Then read
[the behavior tests](ordered_batch_test.exs).

## Run it

```sh
mix test.examples examples/04_agent_workflows/04_05_ordered_batch
```

Expected result: results keep source order, collected errors keep their
positions, and fail-fast input does not commit.

## Important behavior

`Convert` is named because both batch Flows reuse it. The reducer is used once,
so it stays inline and uses its generated name. Empty Map and Reduce components
produce an empty result without special application code.

## Limits

This example does not prove scheduler start or completion order. Those details
belong to Jido Flow core tests.

## Files

- [Source](ordered_batch.ex)
- [Tests](ordered_batch_test.exs)

Previous: [Parallel Join](../04_04_parallel_join/README.md) | Next: [Bounded Iteration](../04_06_bounded_iteration/README.md)
