# 08_08 Follow One Signal

Follow one request through routing, correlated child work, an uncertain
delivery, idempotent retry, and a final reply.

## What you will learn

- Stable Agent references address the coordinator and worker processes.
- One correlation ID and W3C trace cross three accepted Turns.
- Causation links each generated Signal to the Signal that produced it.
- Retrying the same child request ID prevents duplicate domain work.

## Read the code

Read [the complete Signal journey](signal_journey.ex) first.

## Run it

`mix test.examples examples/08_signals_and_messaging/08_08_follow_one_signal --warnings-as-errors`

Expected result: request `request-7` returns result 8 after two delivery
attempts. The worker records one result even though the first acknowledgement
is lost and the same child Signal is accepted twice.

## Important behavior

- Logical owners: the coordinator owns request completion; the worker owns its
  idempotency record.
- Process owners: their AgentServer activations.
- Canonical state owners: each Agent record for its own state.
- Commit points: three AgentServer Turn commits; the worker commits twice, but
  the second commit repeats no domain calculation.
- Persisted data: coordinator status and worker results through the ETS adapter.
- Retry boundary: two adapter attempts with the same Signal and request ID.
- Idempotency rule: one worker result per request ID.
- Injected failure: the adapter loses the first acknowledgement after acceptance.
- Recovery result: the duplicate reply recovers the accepted result.

The child data includes the coordinator Ref as the explicit reply address. The
application router performs the return call.

## Limits

This is at-least-once delivery, not exactly-once delivery. A request ID must be
unique within the worker's state scope. The local adapter does not prove a
network transport, remote lease, or distributed owner.

## Core Fit and Gaps

Signals, stable Refs, AgentServer Turns, Plugin outbound preparation, trace
context, replies, persistence, and idempotent state compose through public
APIs. Application code still owns child routing and its retry policy.

## Files

- [Source](signal_journey.ex)
- [Tests](signal_journey_test.exs)

Previous: [Trace and causation](../08_07_trace_and_causation/README.md) | Next: [Delivery guarantees](../08_09_delivery_guarantees/README.md)
