# 11_19 Failed Work Recovery

**Status: proposed; README only.** No source or example test exists.

Inspect failed pending work and define a safe, explicit recovery decision.

## Current contract and gap

Cancellation and compatibility rejection exist. A general operator recovery
contract for failed or externally uncertain work has not been agreed. Snapshot
upgrade Actions do not migrate a pending execution.

## Planned proof

- Preserve failed or incompatible records for inspection rather than discarding them.
- Report a bounded, portable reason and the stable operation identity.
- Distinguish retry of failed work, cancellation, and a new request.
- Require an explicit decision for uncertain external I/O. Use provider lookup or
  the same operation ID before repeating an unsafe operation.
- Define when a retry can resume and when compatible code must first be restored.
- Keep evidence needed for pending recovery while bounding obsolete history,
  payloads, inbox entries, result receipts, and duplicate records.

## Limits and open decisions

No public reset, fork, skip-step, or result-injection API is selected here.
Such operations can repeat external I/O and need separate contracts. Automatic
compensation, durable progress streams, recurring calendars, and general
parallel races remain later proposals. No executable proof exists yet.

## Reading and execution

Read the [section contract](../../README.md) and
[Flow control proposal](../flow-control/README.md). There is no run command
or executable evidence yet. Add source and tests after contract review.
Use memory or ETS and controlled clocks for local proofs. Do not claim recovery
after loss of the retained store. Storage failures and process loss must use
explicit barriers, not real-day waits or test retries.

## Integration gate

Requires agreed failure/status and compatibility contracts. Begin with public
inspection and explicit decisions; do not invent reset, skip, fork, or stored
result injection APIs while preparing the example.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_18](../11_18_composed_recovery/README.md)
