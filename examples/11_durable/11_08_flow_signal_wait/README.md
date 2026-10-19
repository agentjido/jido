# 11_08 Flow Signal Wait

**Status: proposed; README only.** No executable example or example test exists.

Step 6 waits for an external event in the same ten-step Flow Turn.

## Current contract and gap

Saved Flow waits and a separate active-Turn input path are not implemented.

## Planned proof

- Save steps 1–5, then save the step 6 wait.
- Deliver a correlated Signal through AgentServer while the Turn remains active.
- Resume steps 7–10 without repeating steps 1–5.
- Accept early input, deduplicate its ID, and recover after acceptance before consumption.

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

Use a wait identity that includes the Turn, component path, and occurrence.
Accept early input only for a valid target, save it before acknowledgement,
and consume it once. Test invalid payloads, duplicate/conflicting delivery IDs,
expiry, inbox overflow, and replies from an earlier occurrence. Define duplicate
record retention. Flow input must bypass the queue of ordinary Turns.

## Integration gate

Requires verified event-wait definitions, waiting status, host input delivery,
and checkpoint/restore. The core gate is saved acceptance and consume-once input
through public AgentServer APIs while ordinary Turns remain postponed.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_07](../11_07_external_uncertainty/README.md) | Next: [11_09](../11_09_flow_timer/README.md)
