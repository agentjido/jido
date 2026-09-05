> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Round-Robin Agent Team

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_08_round_robin_team`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Let role Actors contribute in a fixed repeating order until a stop condition.
- **User story:** As a user, I ask a team to refine a result through bounded turns.
- **Trigger or input:** Start Signal and correlated contribution Signals.
- **Agent state:** Participant order, current index, transcript summary, round count, and stop condition.
- **Actions or Flow:** A coordinator Action selects the next child and evaluates termination after each reply.
- **External interactions:** Child Actors and optional model adapters.
- **Runtime Directives or capabilities:** Emit-to-child and timeout Directives drive each finite turn.
- **Expected result:** The order is stable, the team stops within its round limit, and one final result is selected.
- **Failure cases:** Silent child, malformed contribution, repeated reply, no progress, or round limit.
- **Jido features under pressure:** Turn-taking, child messaging, termination policy, state size, and fairness.
- **Source framework and links:** [AutoGen: RoundRobinGroupChat tutorial](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_08_round_robin_team/round_robin_team.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_08_round_robin_team/round_robin_team_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Bounded participant order works. Separate child contribution Signals and timeout handling are not implemented.

An example-scope gap is not evidence of a core Jido defect.
