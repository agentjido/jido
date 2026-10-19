# 11_17 Turn Receipts

**Status: proposed; README only.** No source or example test exists.

Find accepted work and its final result after the original caller is lost.

## Current contract and gap

Core saves accepted work and completion receipts, but caller handles and queued
Signals are not durable. A public stable request/status/result contract needs
review; this lesson does not assert that one exists.

## Planned proof

- Accept a request with a stable ID and acknowledge only after acceptance is saved.
- Lose the caller and restart the Agent. Find the same logical Turn by its ID.
- Return waiting, runnable, retrying, failed, cancelled, or completed status with
  portable metadata. Do not expose private graph records or runtime references.
- Repeat the same request ID and payload without starting a second Turn.
- Reject reuse of an ID with conflicting payload.
- Recover a lost completion reply and return the saved result without repeating work.
- Define result and duplicate-record retention, expiry, and stale lookup responses.

## Limits and open decisions

This proposal extends acceptance semantics; it does not describe the current
behavior of repeated Signals. The same Signal currently starts a new Turn.
Status reads must not mutate the Agent. Keep payload validation and result
schema/version handling explicit. Do not promise exactly-once external I/O.

## Reading and execution

Read the [section contract](../README.md) and
[Flow control proposal](../flow-control/README.md). There is no run command
or executable evidence yet. Add source and tests after contract review.
Use memory or ETS and controlled clocks for local proofs. Do not claim recovery
after loss of the retained store. Storage failures and process loss must use
explicit barriers, not real-day waits or test retries.

## Integration gate

Requires an agreed core acceptance/result API; it may not need a new upstream
primitive. This is a prerequisite for final chain completion and reconnect in
11_15. Preserve the distinction between temporary caller handles and saved IDs.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_16](../11_16_retry_recovery/README.md) | Next: [11_18](../11_18_composed_recovery/README.md)
