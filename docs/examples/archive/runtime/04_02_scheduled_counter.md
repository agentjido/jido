> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Scheduled Counter

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_02_scheduled_counter`
- **Status:** implemented
- **Complexity level:** 2 - Small runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Show delayed and recurring Signal commands on a small Counter.
- **User story:** As an operator, I request one delayed increment and enable or disable a recurring counter schedule.
- **Trigger or input:** Schedule request, delayed tick, cron enable, or cron cancel Signal.
- **Agent state:** `count`, `schedule_requests`, and `cron_enabled`.
- **Actions or Flow:** Separate Actions request a delayed Signal, handle the later tick, enable Cron, and cancel Cron.
- **External interactions:** Scheduler Plugin runtime and its local timers.
- **Runtime Directives or capabilities:** `Schedule` creates a later tick Signal. `Cron` and `Cancel` add or remove Scheduler Plugin runtime state.
- **Expected result:** One test proves that `Schedule` creates a later tick and therefore a second Turn and state version. One test proves that `Cron` and `Cancel` add and remove Scheduler Plugin runtime state.
- **Failure cases:** The current example does not test restart recovery, duplicate ticks, timezone behavior, invalid cron, or late ticks after cancel.
- **Jido features under pressure:** Scheduler Plugin, runtime commands, later mailbox input, and one commit for each Signal turn.
- **Source framework and links:** [Akka: timers and scheduled messages](https://doc.akka.io/libraries/akka-core/current/typed/interaction-patterns.html), [Jido implementation](../../../../examples/04_runtime/04_01_scheduled_signals/scheduled_counter.ex), and [Jido test](../../../../test/examples/04_runtime/04_01_scheduled_signals/scheduled_counter_test.exs)

## Next pressure

Add restart recovery, duplicate occurrence handling, timezone validation, and a
late-tick-after-cancel case.

## Best-effort implementation

- [Code](../../../../examples/04_runtime/04_01_scheduled_signals/scheduled_counter.ex)
- [Tests](../../../../test/examples/04_runtime/04_01_scheduled_signals/scheduled_counter_test.exs)

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

Current feature: [Scheduled Signals](../../profiles/04_runtime/04_01_scheduled_signals.md).
