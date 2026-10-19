# 11_10 Signal Selection

**Status: proposed; README only.** No executable example or example test exists.

Step 6 selects approval, rejection, or a 30-day timeout.

## Current contract and gap

Example 11_06 supports selection over addressed external events and a timer.
This proposal adds the broader selection cases below.

## Planned proof

- Save all alternatives as one wait.
- Persist one selected result before downstream work starts.
- Test Signal/timeout races, duplicates, and stale timer messages.
- Use serialized acceptance order; at or after the deadline, timeout wins.

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

Save the winner and consumed input together. Remove losing waits and timers.
An accepted pre-deadline reply keeps its eligibility after recovery beyond the
deadline. Test duplicate delivery, cancellation, late replies, and storage
failure on either side of the saved winner transition.

## Integration gate

Requires verified selection output, winner persistence, and losing-wait cleanup.
The core gate is one saved winner across Signal/timeout/cancellation races.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_09](../11_09_flow_timer/README.md) | Next: [11_11](../11_11_suspended_activation/README.md)

## Consolidation

The supported Signal, timer, selection, and suspension contract is taught in
[11_06 Durable Wait](../../11_06_durable_wait/README.md). Keep this file for
its remaining policy and long-duration proof questions. It is not a separate
executable lesson.
