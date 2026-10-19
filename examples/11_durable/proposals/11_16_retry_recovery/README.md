# 11_16 Retry Recovery

**Status: proposed; README only.** No source or example test exists.

Keep retry limits and retry deadlines across AgentServer recovery.

## Current contract and gap

Flow execution already supports retry policy through Runic. Audit which
recovery cases already work before changing it. The AgentServer consumer proof
is missing. See [jido_action #304](https://github.com/agentjido/jido_action/issues/304).

## Planned proof

- Fail a step, save its retry budget and next retry deadline, then stop the Agent.
- Restore during backoff with no running Action task. Use the saved deadline.
- Prove that completed earlier steps do not repeat and attempt limits do not reset.
- Restore at the limit and retain terminal failure without an automatic retry loop.
- Cancel during backoff. Stale wake messages must not restart the Turn.
- Resolve lost checkpoint replies before making another attempt.

## Limits and open decisions

Keep retry state in Runic execution data. Do not add a second attempt counter
or scheduler in AgentServer. Separate Action attempt timeout, retry delay,
wait deadline, caller timeout, and whole-Turn budget. Repeated external I/O
still requires a stable operation ID. This is not inside-Action continuation.

## Reading and execution

Read the [section contract](../../README.md) and
[Flow control proposal](../flow-control/README.md). There is no run command
or executable evidence yet. Add source and tests after contract review.
Use memory or ETS and controlled clocks for local proofs. Do not claim recovery
after loss of the retained store. Storage failures and process loss must use
explicit barriers, not real-day waits or test retries.

## Integration gate

Requires verified upstream retry state and status. Audit existing behavior
first. The core gate is retained attempt limits and deadlines after restart,
with cancellation and no Action task during backoff.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_15](../11_15_execution_rollover/README.md) | Next: [11_17](../11_17_turn_receipts/README.md)
