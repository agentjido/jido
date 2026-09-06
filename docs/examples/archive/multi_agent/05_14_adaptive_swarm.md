> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Adaptive Swarm

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_14_adaptive_swarm`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Change a bounded work policy from measured outcomes.
- **User story:** As an operator, I let a swarm select among approved policies without losing control.
- **Trigger or input:** Outcome, evaluation, policy proposal, approval, and generation Signals.
- **Agent state:** Approved policy set, active policy, evidence, scores, generation, budget, and rollback point.
- **Actions or Flow:** An evaluator Flow scores outcomes and proposes a policy change for explicit approval.
- **External interactions:** Fixture environment and optional model-based evaluator.
- **Runtime Directives or capabilities:** Schedule experiments, start bounded workers, publish observations, and roll back runtime topology.
- **Expected result:** Only approved policies activate, and rollback restores the prior known policy.
- **Failure cases:** Reward error, policy drift, unsafe proposal, approval timeout, or rollback failure.
- **Jido features under pressure:** Policy versioning, human control, evaluation, dynamic topology, and rollback.
- **Source framework and links:** [CrewAI: training and planning](https://docs.crewai.com/), [Google ADK: evaluation](https://google.github.io/adk-docs/evaluate/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_14_adaptive_swarm/adaptive_swarm.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_14_adaptive_swarm/adaptive_swarm_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Policy proposal, approval, and rollback state work. Experiments and live topology rollback are not implemented.

An example-scope gap is not evidence of a core Jido defect.
