> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Swarm Control

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_25_swarm_control`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Control more than 100 bounded worker Actors with stable cleanup.
- **User story:** As an operator, I scale a large job while one failure does not stop unrelated work.
- **Trigger or input:** Demand, allocation, result, health, scale, drain, and stop Signals.
- **Agent state:** Desired partitions, worker generations, leases, aggregate progress, budgets, and phase.
- **Actions or Flow:** Partition controllers reconcile local workers and report compact summaries.
- **External interactions:** Local Actor processes and Signal Bus.
- **Runtime Directives or capabilities:** Large bounded batches of spawn, stop, schedule, and Signal delivery commands.
- **Expected result:** All work settles once and full stop removes every process and subscription.
- **Failure cases:** Directive batch limit, mailbox overload, hot partition, mass failure, or incomplete cleanup.
- **Jido features under pressure:** Scale, backpressure, Directive limits, supervision, telemetry volume, and cleanup.
- **Source framework and links:** [Akka: cluster sharding concepts](https://doc.akka.io/libraries/akka-core/current/typed/cluster-sharding-concepts.html)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_25_swarm_control/swarm_control.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_25_swarm_control/swarm_control_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: A 120-worker logical partition plan works. Live Actor scale, failure, backpressure, and complete process/subscription cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
