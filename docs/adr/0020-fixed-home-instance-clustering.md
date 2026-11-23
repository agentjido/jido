# ADR 0020 Fixed home for a clustered Jido instance

- Status: Accepted
- Date: 2026-11-23

## Context

A stable Agent Address carries a namespace, partition and ID. Each BEAM has
a local Registry. Two instances can activate the same durable record from a
shared store. Loss of a BEAM link can leave both processes alive.

## Decision

Configure one home per opted-in namespace. Use `:erpc` for a single remote
dispatch. Ingress starts without the Agent tree or persistence. The home owns
the supervised activation tree, managed persistence, and Wake. A durable home
checks the canonical home and generation before opening the namespace.

Move a namespace only after the operator confirms the old home has stopped and
blocks its restart. Write the new home with an exact compare-and-swap. Transport
failure can leave a mutation's outcome unknown. Read retained results by Turn ID.

## Consequences

The home remains fixed across partitions. A durable move can restore the same
Address and scheduled Turn. Automatic takeover requires a separate decision and
an authority that checks the grant in each protected transaction. The fixed-home
path requires only native OTP.

## References

- [Operations and migration guide](../guides/fixed-home-clustering.md)
- [Two-node integration examples](../../examples/26_distributed_agents/README.md)
