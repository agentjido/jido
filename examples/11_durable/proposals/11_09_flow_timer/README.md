# 11_09 Flow Timer

**Status: proposed; README only.** No executable example or example test exists.

A timer is a saved Flow control step, with no long-running Action.

## Current contract and gap

Example 11_06 supports saved Flow timers and restores their UTC deadlines.
This proposal adds a separate timer demonstration and the cases below.

## Planned proof

- Save one absolute UTC deadline when the timer becomes eligible.
- Restart the Agent before expiry and retain the same deadline.
- Activate after expiry and complete the timer once.
- Test forward and backward clock changes with a controlled clock.

## Ownership and limits

Flow data and DSL belong to `jido_action`. AgentServer owns saved execution,
input acceptance, and recovery. Use memory or ETS for local runtime tests.
Jidoka can later supply retained storage and activation of inactive Agents.
Memory and ETS do not survive loss of their retained data. No Postgres adapter,
cluster ownership, or exactly-once external I/O is part of this example.

## Reading and execution

Read the [DSL proposal](../flow-control/README.md), then the
[section contract](../../README.md). There is no run command or executable evidence yet.
Add source and behavior tests only after the DSL and runtime contracts are agreed.
Use a controlled clock and explicit barriers; do not wait for real days.

## Research decisions to prove

Test restoration before and after the absolute deadline with a controlled clock.
A stale timer wake must not change a resolved or cancelled wait. Distinguish
wait expiry from Action timeout, caller timeout, and whole-Turn timeout.

## Integration gate

Requires verified timer definitions, absolute deadline handling, and clock/wake
integration. The core gate is a saved deadline that survives restore; a local OTP
timer is only a wake mechanism.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_08](../11_08_flow_signal_wait/README.md) | Next: [11_10](../11_10_signal_selection/README.md)

## Consolidation

The supported Signal, timer, selection, and suspension contract is taught in
[11_06 Durable Wait](../../11_06_durable_wait/README.md). Keep this file for
its remaining policy and long-duration proof questions. It is not a separate
executable lesson.
