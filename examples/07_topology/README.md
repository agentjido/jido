# Topology examples

A normal Agent definition contains named Agents and output connections.
AgentServer applies that data under its OTP supervisor. Pure construction
starts no processes.

## Learning order

1. [07_01 Named Agents](07_01_independent/README.md) — initial state, independent commits, JSON parity, and shutdown.
2. [07_11 Direct Connections](07_11_direct_connections/README.md) — root → worker → sink → root, output contracts, and explicit emission.
3. [07_03 Local Bus Broadcast](07_03_bus_swarm/README.md) — declared Bus and counted broadcast.
4. [07_02 Nested Agents](07_02_hierarchy/README.md) — nested ownership and subtree removal.
5. [07_09 Topology Mutations](07_09_topology_mutations/README.md) — member edits, state-bound resize, and repeated File-backed hibernate/thaw.
6. [07_12 Connection Changes](07_12_connection_changes/README.md) — edit edges without replacing Agents, then restore and route through the saved edge.

IDs remain stable even when the recommended reading order differs.

## Run the section

```sh
mix test test/examples/07_topology --include example --seed 0
```

The [Cell Agent](support/cell.ex) supports member and Bus lessons. The
[shared test assertions](../../test/examples/support/agent_topology_assertions.ex)
observe readiness and shutdown through AgentServer and OTP APIs.

## Limits

Delivery uses best-effort casts and separate commits. A parent snapshot saves
its definition, state, topology intent, and code references. It does not save
the current state of every running member. Tests compare portable snapshots:
module references become captured nested definitions at the storage boundary.
There is no separate Controller, placement engine, graph runtime, distributed
ownership, or coordinated multi-Agent checkpoint.

For child creation selected by a Turn, see [dynamic child lifecycle](../05_multi_agent/05_01_child_lifecycle/README.md).
Topology declares members and connections as Agent definition data.
