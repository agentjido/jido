> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Burst Buncher

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_01_burst_buncher`
- **Status:** implemented
- **Complexity level:** 2 - Small runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Collect a burst and flush it by size or timeout.
- **User story:** As a downstream worker, I receive stable batches instead of many small events.
- **Trigger or input:** Item Signals plus an internal flush Signal.
- **Agent state:** Buffered items, batch generation, maximum size, delay, and last flush reason.
- **Actions or Flow:** One Action appends an item or drains the current batch.
- **External interactions:** None.
- **Runtime Directives or capabilities:** A Scheduler Directive replaces the pending flush timer. An `Emit` sends the batch after commit.
- **Expected result:** A batch flushes once by size or time, and no item appears twice.
- **Failure cases:** Late timer from an old generation, duplicate item, oversize item, delivery failure, or stop with data.
- **Jido features under pressure:** Mailbox order, timer replacement, stale Signal rejection, batch state, and delivery.
- **Source framework and links:** [Akka: Buncher timer example](https://doc.akka.io/libraries/akka-core/current/typed/interaction-patterns.html), [Jido implementation](../../../../lib/examples/04_runtime/04_02_keyed_timers/burst_buncher.ex), and [Jido test](../../../../test/examples/04_runtime/04_02_keyed_timers/burst_buncher_test.exs)

## Burn-in result

Four local tests pass. Size and timeout flushes preserve input order. A keyed
timer replacement prevents an old timer from flushing a newer batch. Stable
item IDs prevent duplicate items.

The example needs an example-local Timer Plugin because the current Scheduler
supports delayed Signals but does not support keyed replacement for one-shot
timers. The Timer is a valid runtime capability, but its Plugin, two Directive
types, and runtime process are substantial ceremony for this common pattern.

## Best-effort implementation

- [Code](../../../../lib/examples/04_runtime/04_02_keyed_timers/burst_buncher.ex)
- [Tests](../../../../test/examples/04_runtime/04_02_keyed_timers/burst_buncher_test.exs)

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

Current feature: [Keyed Timers](../../profiles/04_runtime/04_02_keyed_timers.md).
