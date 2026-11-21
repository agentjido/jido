# ADR 0006: Keep dynamic Agent ownership local and activation-scoped

- Status: Accepted
- Date: 2026-11-13

## Context

Applications can start independent Agents with stable Addresses, but they need
a safe way to adopt a resident Agent, transfer it to another live owner, and
stop it when that owner activation ends. An Agent-state ledger can record a
domain owner, but it cannot change runtime shutdown behavior. A durable or
distributed lease would also need storage transactions, node-failure policy,
and an authority model that Jido does not have.

The activation root already survives AgentServer worker replacement. It is the
smallest local boundary that can own a monitor and a fencing generation without
changing portable Agent state.

## Decision

Use `Jido.transfer_agent_ownership/4` as the one public adoption and transfer
operation. The operation accepts stable child and owner Addresses in the same
live instance and partition. Adoption requires `expected: nil`. Transfer
requires the exact current `Jido.AgentOwnership` value. Each accepted relation
gets a fence that includes the child activation identity and an ownership
generation.

A required request ID makes the last accepted request idempotent until another
transfer succeeds. Ownership changes are serialized for one instance and
partition. The operation rejects self-ownership, cycles, stale fences,
unavailable ancestry, and static topology ownership.

The child activation monitors the owner activation root. Transfer replaces the
monitor and runtime record before it returns success. It does not cancel,
restart, or replay an accepted Turn. Work that already captured runtime context
keeps that context. A later Turn captures the current owner.

Keep ownership in the child activation table, outside Agent state, local
checkpoints, and persistence records. It survives worker replacement inside
the same activation. It ends when the child activation passivates, is replaced,
or stops with the Jido instance.

## Consequences

- Applications get public local adoption, fenced transfer, process continuity,
  and owner-linked shutdown.
- A stale owner cannot transfer a newer relation.
- Stopping an old owner after a successful transfer does not stop the child.
- Stopping the current owner stops the complete child activation.
- Reactivation starts unowned and returns a new activation-specific fence after
  adoption.
- Durable ownership, cross-partition ownership, remote placement, authorization,
  and automatic failover remain separate future contracts.

## References

- `Jido.transfer_agent_ownership/4`
- `Jido.agent_ownership/2`
- `Jido.AgentOwnership`
- Covenant obligation `jido.instance.I10`
- [09_05 Runtime ownership transfer](../../examples/09_dynamic_agent_composition/09_05_logical_ownership_transfer/README.md)
