# 11_12 Ninety-Day Flow

**Status: proposed; README only.** No executable example or example test exists.

A Flow runs across 90 days through several saved waits.

## Current contract and gap

Long Turn deadlines exist. Saved waits and a controlled durable-wait clock do not yet exist.

## Planned proof

- Set a Turn budget that covers the complete Flow, or use :infinity.
- Advance a controlled clock across 30-day and 90-day boundaries.
- Recover repeatedly without resetting deadlines or repeating completed steps.
- Test cancellation, bounded local timers, and overdue activation.

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

Elapsed time and history size are separate limits. Use several saved waits
with a controlled clock, and preserve the whole-Turn budget across recovery.
See [execution rollover](../11_15_execution_rollover/README.md) for bounded
active graph data and [retry recovery](../11_16_retry_recovery/README.md) for
saved backoff. A new Turn gets a new Turn budget. Preserve an explicit absolute chain deadline
when rollover must remain within a 90-day overall limit.

## Integration gate

Requires 11_08–11_11 and verified clock/deadline behavior. The core gate is
controlled 90-day progression with no running Action during waits and no reset
of the saved Turn deadline. Chain rollover is a separate proof in 11_15.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_11](../11_11_suspended_activation/README.md) | Next: [11_13](../11_13_topology_wait/README.md)
