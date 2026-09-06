> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Audit Outbox

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_04_audit_outbox`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Record audit intent only for a successful complete Flow.
- **User story:** As an auditor, I see a durable record for committed business work.
- **Trigger or input:** A business Signal that selects an audited Flow.
- **Agent state:** Business state plus Audit Plugin state with ordered records.
- **Actions or Flow:** A Flow performs work and returns final state with audit Directives.
- **External interactions:** Audit sink. The test uses a local runtime.
- **Runtime Directives or capabilities:** Audit Plugin Directives dispatch records after the Actor state commits.
- **Expected result:** One successful Flow commits one success and one Audit Plugin event, then the runtime receives the same event. One later failed Flow keeps Actor and runtime state unchanged and exposes a failed, uncommitted Outcome.
- **Failure cases:** The test covers an execute-stage Flow error. Invalid Directive, persistence failure, audit dispatch failure, restart, and several ordered records are not covered.
- **Jido features under pressure:** Plugin contribution, outbox order, one commit, post-commit failure, and sensitive metadata.
- **Source framework and links:** [CrewAI: event listeners](https://docs.crewai.com/en/concepts/event-listener), [Jido integration example](../../../../examples/08_applications/08_01_audit/audit.ex)

## Next pressure

Record several audit Directives in order and test runtime restart and dispatch
failure.

## Best-effort implementation

- [Code](../../../../examples/04_runtime/04_08_commit_outbox/audit_outbox.ex)
- [Tests](../../../../test/examples/04_runtime/04_08_commit_outbox/audit_outbox_test.exs)

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

Current feature: [Commit Outbox](../../profiles/04_runtime/04_08_commit_outbox.md).
