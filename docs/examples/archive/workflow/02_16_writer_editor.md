> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Writer and Editor

- **ID:** `02_16_writer_editor`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Pass one work product through two role-specific stages.
- **User story:** As a publisher, I receive a draft and a reviewed final copy.
- **Trigger or input:** `content.write` Signal with topic, brief, and style rules.
- **Agent state:** Brief, draft, edit notes, final copy, and stage outcomes.
- **Actions or Flow:** A sequential Flow calls a writer adapter and then an editor adapter.
- **External interactions:** Two model calls. The local test uses two deterministic fake agents.
- **Runtime Directives or capabilities:** An optional `Emit` sends the approved content after commit.
- **Expected result:** The final copy and edit record commit one time.
- **Failure cases:** Writer error, empty draft, editor error, policy rejection, or output too large.
- **Jido features under pressure:** Step contracts, role separation, model adapters, one commit, and trace correlation.
- **Source framework and links:** [Mastra: multi-agent workflow](https://mastra.ai/en/examples/agents/multi-agent-workflow), [CrewAI: guide writer and reviewer](https://docs.crewai.com/en/guides/flows/first-flow)

## Burn-in result

The local example passes. Separate writer and editor adapter contracts run in
two Flow steps. Draft, review notes, and final copy commit together. An editor
failure leaves Actor state unchanged.

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_16_writer_editor/writer_editor.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_16_writer_editor/writer_editor_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
