> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Medical Agent Delegation

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_21_medical_delegation`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** true integration

## Profile

- **Purpose:** Route a case among medical information specialists with mandatory safety controls.
- **User story:** As a clinician, I receive evidence support while all final decisions stay with an authorized human.
- **Trigger or input:** Case Signal with de-identified data and explicit task scope.
- **Agent state:** Case reference, consent, specialist assignments, evidence, uncertainty, approvals, and audit status.
- **Actions or Flow:** A coordinator Flow delegates narrow evidence tasks and blocks any unapproved external action.
- **External interactions:** Clinical data, literature services, models, and human review.
- **Runtime Directives or capabilities:** Secure input, audit, approval notification, and controlled output capabilities.
- **Expected result:** The output preserves evidence, uncertainty, and human ownership.
- **Failure cases:** Identity failure, sensitive data leak, unsupported advice, stale evidence, or missing approval.
- **Jido features under pressure:** High-stakes policy, identity, secure state, durable approval, audit, and source provenance.
- **Source framework and links:** [PydanticAI: medical agent delegation](https://pydantic.dev/docs/ai/examples/complex-workflows/medical-agent-delegation/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_21_medical_delegation/medical_delegation.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_21_medical_delegation/medical_delegation_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: De-identified evidence, uncertainty, and human ownership work. Durable approval, secure transport, and controlled clinical integrations are not implemented.

An example-scope gap is not evidence of a core Jido defect.
