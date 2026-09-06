> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Deduplicating Inbox

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_05_deduplicating_inbox`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Accept a burst from an input Plugin and process each event once.
- **User story:** As an event consumer, I keep correct state through duplicates and input runtime restarts.
- **Trigger or input:** External input events that the Plugin converts to Actor Signals.
- **Agent state:** Seen event IDs, processed items, input Plugin state, and counters.
- **Actions or Flow:** A Flow validates the event, checks the duplicate ledger, and applies new work.
- **External interactions:** Input process. The test uses a local fixture producer.
- **Runtime Directives or capabilities:** Plugin runtime capabilities receive events and send Signals through the Actor mailbox.
- **Expected result:** Unique events commit once, duplicates are ignored, and restart does not lose committed input state.
- **Failure cases:** Malformed event, concurrent duplicate, runtime restart, overload, or state limit.
- **Jido features under pressure:** Input Plugin, mailbox admission, deduplication, burst order, and runtime recovery.
- **Source framework and links:** [Sagents: middleware messaging](https://hexdocs.pm/sagents/middleware_messaging.html), [Jido integration example](../../../../examples/08_applications/inbox/inbox.ex)

## Best-effort implementation

- [Code](../../../../examples/04_runtime/04_07_input_deduplication/deduplicating_inbox.ex)
- [Tests](../../../../test/examples/04_runtime/04_07_input_deduplication/deduplicating_inbox_test.exs)

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

Current feature: [Input Deduplication](../../profiles/04_runtime/04_07_input_deduplication.md).
