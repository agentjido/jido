> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Sequential Data Flow

- **ID:** `02_11_sequential_data_flow`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Show several dependent steps inside one Flow and one terminal commit.
- **User story:** As a user, I submit raw records and receive validated, normalized, and summarized output.
- **Trigger or input:** `data.process` Signal with fixture records.
- **Agent state:** Input digest, normalized records, summary, and completion status.
- **Actions or Flow:** A Flow validates, normalizes, enriches, and summarizes data in fixed order.
- **External interactions:** An optional enrichment adapter. The local test uses a fixed in-memory map.
- **Runtime Directives or capabilities:** An optional `Emit` publishes the summary after the Actor state commits.
- **Expected result:** All steps succeed and the complete output commits one time.
- **Failure cases:** Validation error, enrichment timeout, malformed response, or a failed terminal step.
- **Jido features under pressure:** Flow step data, error propagation, effectful steps, and no partial Actor state.
- **Source framework and links:** [Semantic Kernel: sequential orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/sequential)

## Burn-in result

The local example passes. One Signal selects a four-step Flow. Result
references order validation, normalization, enrichment, and summary. The Flow
returns one complete state, and the Actor Server increments its state version
one time. A failed intermediate step does not commit partial Actor state.

No Jido core change was necessary.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_11_sequential_data_flow/sequential_data_flow.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_11_sequential_data_flow/sequential_data_flow_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
