> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Session Compaction Policy

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_10_session_compaction_policy`
- **Status:** implemented
- **Complexity level:** 3 - Context management
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Reduce model context while preserving durable Agent state and the original Thread history.
- **User story:** As a user, I continue a long Agent session without losing task state, audit facts, or important decisions.
- **Trigger or input:** A compaction Signal contains the current context budget and a bounded Thread selection.
- **Agent state:** Original Thread, active context projection, summary entry, retained references, token estimate, and compaction version.
- **Actions or Flow:** One effectful Flow calls a fake summarizer, validates its references, builds a new context projection, and commits once.
- **External interactions:** Fake summarizer and token estimator.
- **Runtime Directives or capabilities:** A context-threshold observer can send the compaction Signal. It does not modify the active Turn.
- **Expected result:** The active model context becomes smaller, durable Thread entries stay unchanged, task state stays unchanged, and retry uses the committed projection.
- **Failure cases:** Summarizer error, invalid reference, lost decision, budget still exceeded, concurrent new message, repeated compaction, or retry loop.
- **Jido features under pressure:** Thread projections, effectful Flow, validation, one commit, Signal scheduling, retry, and separation of durable state from model context.
- **Source framework and links:** [Pi compaction lifecycle](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md) and [Pi custom compaction examples](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions)


## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_10_session_compaction_policy/session_compaction_policy.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_10_session_compaction_policy/session_compaction_policy_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
