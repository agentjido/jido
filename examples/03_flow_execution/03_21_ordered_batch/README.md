# Ordered Batch

Map processes a collection while Reduce builds one ordered Agent result.

## What you will learn

- How `max_concurrency` bounds active Map items while results keep input order.
- How collected and fail-fast error policies differ.
- How Reduce consumes successful Map output and handles an empty collection.

## Read the code

Read [the Agent and two Flows](ordered_batch.ex) first. Then read
[the behavior tests](ordered_batch_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_21_ordered_batch --warnings-as-errors
```

Expected result: results keep source order, collected errors keep their
positions, fail-fast input does not commit, and a fifth item waits for one
of four active items to complete.

## Important behavior

`Convert` is shared by both batch Flows. Empty Map and Reduce components
produce an empty result. Pass `max_concurrency` in the execution options when
starting an Agent or calling `Jido.Exec.run/4`. The concurrency test uses a local
probe to hold workers until the test releases them.

## Limits

The proof covers the local concurrency bound for one Map execution.

## Files

- [Source](ordered_batch.ex)
- [Agent tests](ordered_batch_test.exs)
- [Concurrency test](concurrency_test.exs) and its [probe](support/concurrency_probe.exs)

Previous: [Parallel Join](../03_20_parallel_join/README.md) | Next: [Bounded Iteration](../03_22_bounded_iteration/README.md)
