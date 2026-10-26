# 11_18 Composed Recovery

**Status: proposed; README only.** No source or example test exists.

Recover waits inside repeated and nested Flow components without identity collisions.

## Current contract and gap

Lower-level component recovery evidence exists, but it does not prove pending
wait recovery through AgentServer. Parallel, nested, Map, and Iterate consumer
claims remain limited. See [jido_action #305](https://github.com/agentjido/jido_action/issues/305).

## Planned proof

- Wait twice in Iterate; a delayed reply for occurrence one must not satisfy two.
- Keep separate identities for Map items, including equal input values.
- Restore a nested Flow wait without repeating completed parent or sibling work.
- Restore a wait in an Invoke-selected Flow.
- Cancel the parent Turn and remove descendant waits and timers.
- Preserve saved partial results; test parallel recovery separately from serial cases.
- Reject unsupported compositions before any external work starts.

## Limits and open decisions

Runic remains the graph authority. Flow component ancestry is not Agent topology
or an OTP supervision tree. Selection races event/timer alternatives; it does
not introduce arbitrary Action races. The first implementation may support a
smaller set of compositions, with explicit validation errors for the others.

## Reading and execution

Read the [section contract](../../README.md) and
[Flow control proposal](../flow-control/README.md). There is no run command
or executable evidence yet. Add source and tests after contract review.
Use memory or ETS and controlled clocks for local proofs. Do not claim recovery
after loss of the retained store. Storage failures and process loss must use
explicit barriers, not real-day waits or test retries.

## Integration gate

Requires verified upstream support for each composition. Build one supported
case at a time; reject unsupported combinations before external work. No general
parallel-support claim follows from a passing serial wait example.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_17](../11_17_turn_receipts/README.md) | Next: [11_19](../11_19_failed_work_recovery/README.md)
