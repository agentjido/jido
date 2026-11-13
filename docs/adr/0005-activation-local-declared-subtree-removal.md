# ADR 0005: Activation-local declared-subtree removal

- Status: Accepted
- Date: 2026-11-13

## Context

A static Agent topology starts a fixed set of member slots. Applications can
stop the complete root activation, but they also need to stop one department
or team subtree while the root stays active.

The operation must not turn live process state into a second topology
definition. It must also control new admission, accepted Turns, durable child
state, shutdown order, and partial failure.

## Decision

Add `Jido.AgentServer.remove_topology_member/4`. The caller selects one
declared member name and slot in the current root activation.

The operation records activation-local removal intent before cleanup. It stops
new topology delivery to the selected slot, closes admission for the selected
member and all owned descendants, and finishes accepted Turns by default. The
caller can select pre-commit cancellation. After the subtree is quiescent, the
runtime stops descendants before their parent.

The static Agent definition does not change. Durable child records are not
deleted. Removal intent survives root-worker recovery in the same activation,
but it does not survive replacement of the root activation.

A repeated removal returns `:ok`. If quiescence or shutdown cannot finish in
the time limit, the operation returns an incomplete-removal error. Removal
intent and closed admission stay in place. A repeated call continues cleanup.

## Consequences

The root and sibling subtrees can continue to accept work during removal. A
caller can retry cleanup without restoring a partly stopped subtree.

A replacement root activation builds the static topology again. With
persistence, each member restores its saved state. Applications that need a
membership change that survives root replacement must install a new static
definition or use separately owned dynamic Agents.

The operation does not provide one atomic checkpoint for the parent and all
children.

See the [AgentServer component](../components/agent_server.md) and the
[composition contract](../../test/contracts/jido.agent_server/composition.obligations.md).
