> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Customer Feedback Summarizer

- **ID:** `02_03_feedback_summarizer`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Convert many feedback items into themes and action records.
- **User story:** As a product manager, I receive a short theme report from customer comments.
- **Trigger or input:** `feedback.summarize` Signal with a bounded batch of comments.
- **Agent state:** Input digest, themes, evidence IDs, sentiment totals, and recommended actions.
- **Actions or Flow:** A Flow cleans comments, groups them, summarizes each group, and validates evidence links.
- **External interactions:** Optional model. Local tests use fixed grouping and summary adapters.
- **Runtime Directives or capabilities:** An `Emit` can send recommended actions to a planning Actor after commit.
- **Expected result:** Each theme cites input IDs and totals match the input batch.
- **Failure cases:** Oversize batch, unsafe content, model error, lost evidence link, or invalid totals.
- **Jido features under pressure:** Batch limits, structured output, evidence integrity, and downstream Signal design.
- **Source framework and links:** [Mastra: customer feedback template](https://mastra.ai/docs)

## Burn-in result

The local example passes. A Flow validates the batch, maps a cleaning Action
over comments, calls a fixture summarizer, and rejects themes that lose or
invent evidence IDs. It does not need a Plugin.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_03_feedback_summarizer/feedback_summarizer.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_03_feedback_summarizer/feedback_summarizer_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
