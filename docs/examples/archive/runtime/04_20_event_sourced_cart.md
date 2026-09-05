> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Event-Sourced Cart

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_20_event_sourced_cart`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Rebuild cart state from an append-only domain event history.
- **User story:** As an operator, I inspect every cart transition and restore any past version.
- **Trigger or input:** Add item, remove item, checkout, snapshot, or replay command.
- **Agent state:** Current cart projection, sequence number, and snapshot marker.
- **Actions or Flow:** One Action validates a command and produces domain events that fold into state.
- **External interactions:** Event journal and snapshot store.
- **Runtime Directives or capabilities:** Journal append and snapshot control need durable runtime commands tied to the commit.
- **Expected result:** Replay produces the same state and rejected commands append no event.
- **Failure cases:** Append conflict, corrupt event, schema migration, duplicate command, or snapshot mismatch.
- **Jido features under pressure:** Jido has snapshot-style persistence and an effect outbox, but no public domain event journal contract.
- **Source framework and links:** [Akka: Event Sourcing](https://doc.akka.io/libraries/akka-core/current/typed/persistence.html)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_20_event_sourced_cart/event_sourced_cart.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_20_event_sourced_cart/event_sourced_cart_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: The event fold works, but atomic domain-event journal append tied to Actor commit is missing.

An example-scope gap is not evidence of a core Jido defect.
