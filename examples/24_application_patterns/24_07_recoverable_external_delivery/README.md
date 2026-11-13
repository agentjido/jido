# 24_07 Recoverable External Delivery

This application saves external delivery intent with Agent state, survives
process loss, retries an uncertain outcome with one stable effect ID, and
commits acknowledgement after the idempotent sink confirms the record.

## What you will learn

- How a Plugin owns delivery state, Directives, a supervised worker, and
  post-commit dispatch as one vertical capability.
- How an external system can apply a write and still return an uncertain
  outcome.
- How stable effect identity makes retry safe and acknowledgement explicit.
- Where explicit compensation belongs after reconciliation proves that a
  committed external change must be reversed.

## Read the code

Read the [Agent](../../12_persistence/12_07_recoverable_delivery/recoverable_delivery.ex),
the [Plugin](../../12_persistence/12_07_recoverable_delivery/delivery_plugin.ex),
the [worker](../../12_persistence/12_07_recoverable_delivery/delivery_worker.ex),
and the [idempotent sink](../../12_persistence/12_07_recoverable_delivery/support/memory_sink.ex).
Then read the [compensation pattern](../24_05_compensation/README.md).

## Run it

`mix test.examples examples/24_application_patterns/24_07_recoverable_external_delivery --warnings-as-errors`

Expected result: delivery intent commits while the sink is unavailable. After
process replacement, the sink writes once but reports an uncertain result. A
retry with the same effect ID succeeds, and the Agent commits acknowledgement.

## Important behavior

The Agent record is the canonical owner of pending delivery intent. The sink is
the canonical owner of the external record. The state commit occurs before
delivery. Delivery can repeat. Confirmation is a later Agent Turn. Compensation
must use its own stable operation ID and only start after outcome reconciliation;
the separate compensation lesson proves that branch.

## Limits

The memory sink is not durable and cannot reproduce a real network partition.
The delivery and compensation examples are separate protocols, not one atomic
transaction. Completed effect IDs need a retention policy.

## Core Fit and Gaps

Plugin vertical ownership, commit-before-effects, supervised runtime children,
persistence, and stable Agent references compose into recoverable delivery.
Ordinary Directives alone do not promise replay. The Plugin makes pending work
durable and the external adapter makes repeated delivery idempotent.

- Logical owner: delivery Agent reference.
- Process owner: current AgentServer and Plugin worker activation.
- Canonical state owner: Agent Plugin state for intent; sink for external
  record.
- Commit point: pending intent commit, followed later by confirmation commit.
- Persisted data: pending and completed effect IDs and values.
- Retry boundary: one sink delivery by stable effect ID.
- Idempotency rule: the same effect ID and value is success; a different value
  is a conflict.
- Injected failure: unavailable sink, process loss, then uncertain outcome.
- Recovery result: one external record and one completed acknowledgement.
- Limits and non-guarantees: no distributed transaction spans Agent and sink.

## Files

- [Tests](recoverable_external_delivery_test.exs)
- [Compensation lesson](../24_05_compensation/README.md)

[Previous: Phoenix LiveView chat](../24_06_phoenix_liveview_chat/README.md)

[Next: Controlled Agent Upgrade](../24_08_controlled_agent_upgrade/README.md)
