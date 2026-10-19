# 11_11 Suspended Activation

**Status: proposed; README only.** No executable example or example test exists.

A waiting Flow releases execution resources and resumes after activation.

## Current contract and gap

Current hibernation drains or cancels active work. Saved waiting-Turn deactivation needs a new contract.

## Planned proof

- Release the runner and Action tasks while retaining the current Turn.
- Suspend and deactivate without applying the current drain/cancel hibernation behavior.
- Activate the same Agent and restore its wait and deadline.
- Keep ordinary state-changing commands serialized; permit status and cancellation.

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

A saved wait has no running Action task. A reply must release the wait even
when ordinary state-changing Turns are queued. Status and cancellation stay
available. Rebuild runtime resources from portable saved data on activation.

## Integration gate

Requires verified wait serialization, runner release, and resume. The core gate
is pending-Turn deactivation through the existing supervision tree. Do not
reinterpret current drain/cancel hibernation without an agreed public contract.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_10](../11_10_signal_selection/README.md) | Next: [11_12](../11_12_ninety_day_flow/README.md)
