# ADR 0002: Restore or create durable Agent activation

- Status: Superseded
- Date: 2026-11-03
- Superseded by: [Jido durable Agent activation plan](../architecture/durable-agent-activation.md)

## Context

A caller with a stable Agent Address must not first test storage and then choose a start function. That check has a race. Strict create and strict restore operations are still useful for lifecycle control.

## Decision

`Jido.activate_agent/4` is the restore-or-create operation for one stable Address.

It first returns the current local activation when one exists. Otherwise, Persistence reads the durable record. It restores an active record. It creates revision zero only after a not-found read. If that create conflicts, it reads and restores the winning record.

A tombstone, an invalid record, and another storage error do not become a create operation. The former `Jido.start_agent_ref/4` API and `Jido.thaw/4` keep their strict create and restore meanings.

## Consequences

- A caller can use one operation for first start and later restart.
- Concurrent activation uses Registry and storage compare-and-swap to select one winner.
- Deleted or damaged records cannot silently become new Agents.
- The activation can return a recovering server. The caller can use `Jido.AgentServer.await_ready/2`.

## References

- `Jido.activate_agent/4`
- `Jido.Persistence.open_agent/4`
- Covenant obligation `jido.instance.I9`
