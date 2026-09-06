# Ordered Batch

- **ID:** `02_05_ordered_batch`
- **Status:** implemented
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

Ordered Map results, collected errors, fail-fast commit behavior, empty input, and serial Reduce.

## Acceptance cases

- Reverse Map completion feeds an ordered serial Reduce.
- Collected errors keep their source position under reversed completion.
- At concurrency one, fail-fast stops pending items and rejects the batch and
  its dependent Reduce, regardless of which item starts first.
- Empty Map and Reduce return their empty result without invoking a body.

## Implementation and evidence

- [Source](../../../../examples/02_workflow/02_05_ordered_batch/ordered_batch.ex)
- [Integration tests](../../../../test/examples/02_workflow/02_05_ordered_batch/ordered_batch_test.exs)
- [Workflow results](../../workflow-results.md)

Uses real Agent routing, Jido.Exec, Jido.Flow, and Server commits. External
adapters and observation callbacks only supply fixed responses and timing
controls. Caller context stays transient unless application code explicitly
copies fields into its output.

## Earlier domain examples

Mixed File Ingestion, Learning Guide, Feedback Summarizer, PDF Flash Cards. See the [research archive](../../archive/workflow/README.md).
