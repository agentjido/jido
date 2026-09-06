> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Support Email Agent

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_12_support_email_agent`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Classify, research, draft, escalate, and schedule follow-up for support email.
- **User story:** As a support team, I receive a safe draft, ticket action, or human escalation.
- **Trigger or input:** Inbound email Signal from an input Plugin.
- **Agent state:** Email ID, classification, urgency, customer history, evidence, draft, approval, and follow-up.
- **Actions or Flow:** A Flow classifies the email, reads data, chooses actions, drafts a reply, and applies review policy.
- **External interactions:** Email, document search, customer service, ticket system, and LLM. Local tests use fixtures.
- **Runtime Directives or capabilities:** Email and ticket Plugin commands run after commit. Scheduler sends follow-up Signals.
- **Expected result:** Each email has one terminal route and all external writes use its stable ID.
- **Failure cases:** Duplicate email, data timeout, wrong urgency, unsafe reply, ticket error, or send error.
- **Jido features under pressure:** Input Plugin, effectful Flow, structured routing, approval, idempotent writes, and schedules.
- **Source framework and links:** [LangGraph: support email agent](https://docs.langchain.com/oss/python/langgraph/thinking-in-langgraph)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_12_support_email_agent/support_email_agent.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_12_support_email_agent/support_email_agent_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Classification, drafting, escalation, and idempotent writes work. Input Plugin delivery, post-commit dispatch, and scheduled follow-up are not implemented.

An example-scope gap is not evidence of a core Jido defect.
