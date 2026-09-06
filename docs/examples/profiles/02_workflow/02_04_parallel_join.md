# Parallel Join

- **ID:** `02_04_parallel_join`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 5

## SDK obligation

Concurrent independent steps, join dependencies, execution limits, failure, and cancellation.

## Command API

```elixir
{:ok, agent} = Jido.Examples.ParallelJoin.fetch_pair(server, 3)
signal = Jido.Examples.ParallelJoin.fetch_pair_signal!(3, :left)
```

The Flow schema supplies `fail: :none` when omitted. An invalid failure selector
is rejected before either branch runs. Constructing a Signal does not execute
or validate the Flow.

## Acceptance cases

- Named commands apply defaults and reject invalid input before either branch.

- Independent work overlaps and the join waits for both results.
- A concurrency limit of one prevents overlap.
- Branch failure permits already started work to finish but prevents the join.
- Cancellation stops every Flow worker and the next Turn uses fresh context.

## Implementation and evidence

- [Source](../../../../examples/02_workflow/02_04_parallel_join/parallel_join.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_04_parallel_join/parallel_join_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Hybrid Search. See the [research archive](../../archive/workflow/README.md).
