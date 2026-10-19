# 11_13 Topology Wait

**Status: proposed; README only.** No executable example or example test exists.

A topology member resumes a waiting Flow from another member’s Signal.

## Current contract and gap

Topology recovery exists. Signals into a waiting active Flow are not implemented.

## Planned proof

- Use stable member and Turn identities for event correlation.
- Restart the member and root supervisor while the Flow waits.
- Retain accepted input across recovery and consume it once.
- Keep independent member records; do not claim an atomic topology snapshot.

## Ownership and limits

Flow data and DSL belong to `jido_action`. AgentServer owns saved execution,
input acceptance, and recovery. Use memory or ETS for local runtime tests.
Jidoka can later supply retained storage and activation of inactive Agents.
Memory and ETS do not survive loss of their retained data. No Postgres adapter,
cluster ownership, or exactly-once external I/O is part of this example.

## Reading and execution

Read the [DSL proposal](../flow-control/README.md), then the
[section contract](../README.md). There is no run command or executable evidence yet.
Add source and behavior tests only after the DSL and runtime contracts are agreed.
Use a controlled clock and explicit barriers; do not wait for real days.

## Research decisions to prove

Request-and-wait needs an explicit boundary. Current Directives run after Turn
commit; they cannot send a request needed to complete a wait in that same Turn.
Do not bypass this gap with raw process messages or a test-only callback.
Agree a public communication contract first. Register or buffer the reply
before sending, use a stable operation ID, and test a repeated outbound request
when the receiver accepted it before the sender saved completion. Local
cancellation cannot undo a request that reached another Agent.

## Integration gate

Requires verified event delivery plus an agreed public request-and-wait
communication boundary. A DSL wait alone does not close the post-commit Directive
gap. Do not add an example-only messaging implementation.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_12](../11_12_ninety_day_flow/README.md) | Next: [11_14](../11_14_recovery_compatibility/README.md)
