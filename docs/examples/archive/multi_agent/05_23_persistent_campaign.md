> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Persistent Campaign

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_23_persistent_campaign`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Run a long-lived goal with persistent coordinators and temporary specialist roles.
- **User story:** As an operator, I pause, resume, inspect, and finish a campaign across many finite turns.
- **Trigger or input:** Goal, observation, task result, review, pause, resume, and tick Signals.
- **Agent state:** Goal, generation, plan, durable roles, temporary tasks, evidence, budget, and phase.
- **Actions or Flow:** Finite planning and settlement Flows create bounded work for child Actors.
- **External interactions:** Fixture environment first; optional models and services later.
- **Runtime Directives or capabilities:** Schedule, spawn, stop, Bus, persistence, and audit commands.
- **Expected result:** The campaign resumes from committed progress and stops with no temporary resource.
- **Failure cases:** Orphan work, duplicate result, stale generation, budget overrun, restart, or cleanup failure.
- **Jido features under pressure:** Long-lived purpose, dynamic topology, persistence, cancellation, and complete cleanup.
- **Source framework and links:** [Google ADK: multi-agent systems](https://google.github.io/adk-docs/agents/multi-agents/), [AutoGen: teams](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_23_persistent_campaign/persistent_campaign.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_23_persistent_campaign/persistent_campaign_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Finite pause, resume, and task-result state work. Persistence recovery, temporary child ownership, and cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
