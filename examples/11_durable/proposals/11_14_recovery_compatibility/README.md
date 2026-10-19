# 11_14 Recovery Compatibility

**Status: proposed; README only.** No executable example or example test exists.

Pending work resumes only with a compatible execution definition.

## Current contract and gap

Core rejects changed execution fingerprints. This lesson has no focused example yet; active-Flow migration is deferred.

## Planned proof

- Restore a wait with unchanged Flow and Action code.
- Reject changed execution code without discarding the saved record.
- Keep Agent snapshot upgrades separate from pending Flow compatibility.
- State the retention requirement for deployed Flow and Action modules.

## Ownership and limits

Flow data and DSL belong to `jido_action`. AgentServer owns saved execution,
input acceptance, and recovery. Use memory or ETS for local runtime tests.
Jidoka can later supply retained storage and activation of inactive Agents.
Memory and ETS do not survive loss of their retained data. No Postgres adapter,
cluster ownership, or exactly-once external I/O is part of this example.

## Reading and execution

Read the [DSL proposal](../flow-control/README.md), then the
[section contract](../../README.md). There is no run command or executable evidence yet.
Add source and behavior tests only after the DSL and runtime contracts are agreed.
Use a controlled clock and explicit barriers; do not wait for real days.

## Research decisions to prove

Cover versioned wait payloads, saved results, and execution context rebuilt
with current runtime services. Do not persist credentials or process handles.
A snapshot upgrade does not authorize pending Flow migration. Rollover is
not an automatic permission to run changed code.

## Integration gate

Requires verified checkpoint and definition version compatibility. The core
gate is compatible restore or explicit rejection that preserves saved work;
snapshot upgrade Actions do not imply active-Flow migration.

Follow the [integration checklist](../flow-control/INTEGRATION.md). Keep this
lesson README-only until the required public contracts are verified.

Previous: [11_13](../11_13_topology_wait/README.md) | Next: [11_15](../11_15_execution_rollover/README.md)
