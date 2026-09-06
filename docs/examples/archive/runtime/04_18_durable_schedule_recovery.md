> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Durable Schedule Recovery

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_18_durable_schedule_recovery`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Restore recurring schedule intent after a complete Actor restart.
- **User story:** As an operator, I do not lose or duplicate scheduled work after a crash.
- **Trigger or input:** Create schedule, scheduled tick, cancel, and restore events.
- **Agent state:** Durable cron definitions, last handled occurrence, generation, and cancellation state.
- **Actions or Flow:** One Action handles each management or tick Signal.
- **External interactions:** Clock and persistence. Tests use controlled time and restart hooks.
- **Runtime Directives or capabilities:** Scheduler Cron and Cancel Directives reconcile runtime timers from committed Plugin state.
- **Expected result:** One logical occurrence causes at most one state change after restore.
- **Failure cases:** Crash near dispatch, duplicate occurrence, missed window, invalid timezone, or cancel race.
- **Jido features under pressure:** Persistent Plugin state, runtime reconciliation, occurrence identity, and at-least-once delivery.
- **Source framework and links:** [Google ADK: Restate durable execution integration](https://google.github.io/adk-docs/integrations/restate/), [Akka: timers](https://doc.akka.io/libraries/akka-core/current/typed/interaction-patterns.html), Jido implementation in `bd05a32` at `examples/99_research/90_legacy/runtime/04_18_durable_schedule_recovery/durable_schedule_recovery.ex`, and Jido test in `bd05a32` at `test/examples/99_research/90_legacy/runtime/04_18_durable_schedule_recovery/durable_schedule_recovery_test.exs`

## Burn-in result

Six local tests pass. Persistent Scheduler Plugin state restores and rebuilds
the CRON runtime. Application state rejects late generations, late ticks after
cancel, and duplicate logical occurrence IDs. Invalid CRON and timezone values
do not commit. A new job ID removes the prior durable schedule.

The complete profile fails. Scheduler stores one static Signal template and
creates a fresh Signal ID for each delivery. It does not create a stable
logical occurrence ID that can survive a crash and redelivery. It also has no
durable dispatch acknowledgement or missed-window policy. The ideal redelivery
test is skipped until this runtime contract exists.

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_18_durable_schedule_recovery/durable_schedule_recovery.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_18_durable_schedule_recovery/durable_schedule_recovery_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: Schedule restore works. Stable logical occurrence identity and durable redelivery acknowledgement are missing.

An example-scope gap is not evidence of a core Jido defect.
