# ADR 0009: Durable topology acceptance

- Status: Proposed
- Date: 2026-11-18

## Context

Topology casts can lose a Signal if either activation fails after the
sender commits. The existing durable Flow receipt can restore one active
Turn. Later Turns can replace that receipt. Public result handoff retains a
terminal result and blocks new Turns until acknowledgment.

## Decision

Let a Turn request durable delivery to one declared parent or child slot in
its local Jido instance. Keep pending sends and accepted handoff IDs in an
optional field of the Agent record. Update this field in the same conditional
write as the sender's next state or the receiver's running Flow receipt. Use
the handoff ID as the receiver Turn ID.

Retry delivery by stable Address. Remove the sender's pending entry after
the receiver confirms acceptance. Keep the receiver acceptance ID through
later Turns. A sender and receiver each use their own revision and can
recover independently.

## Consequences

The receiver can acknowledge before execution completes. A sender crash
before removal can cause another delivery attempt, which the receiver
recognizes by ID. The receiver's acceptance history grows for the lifetime
of its record. The sender's oldest pending send can delay later sends.

The API uses the existing durable Flow recovery policy. Application effects
retain their own recovery limits. See [Durable Topology](../../guides/durability/durable-topology.md).
