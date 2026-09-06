> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Subscription Reconciliation

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_13_subscription_reconciliation`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Repair external subscription state from committed desired state.
- **User story:** As an operator, I keep topic subscriptions correct after dispatch failure or runtime restart.
- **Trigger or input:** Subscribe, unsubscribe, reconcile, or runtime-ready Signal.
- **Agent state:** Desired topics, generation, and last reconcile result.
- **Actions or Flow:** One Action updates desired subscription state.
- **External interactions:** External subscription runtime represented by a local fake.
- **Runtime Directives or capabilities:** Plugin-owned subscribe and unsubscribe Directives change runtime state after commit.
- **Expected result:** Runtime subscriptions converge to committed desired state.
- **Failure cases:** Dispatch failure, repeated command, runtime unavailable, restart, or stale reconcile result.
- **Jido features under pressure:** Plugin state ownership, Directive ordering, reconciliation, and post-commit failure.
- **Source framework and links:** [Akka: distributed publish-subscribe](https://doc.akka.io/libraries/akka-core/current/typed/cluster.html), [Jido integration example](../../../../examples/08_applications/subscription/subscription.ex)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_13_subscription_reconciliation/subscription_reconciliation.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_13_subscription_reconciliation/subscription_reconciliation_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
