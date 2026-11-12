# 10 Topologies

A normal Agent definition contains named Agents and output connections.
AgentServer applies that data under its OTP supervisor. Pure construction
starts no processes.

## Learning order

1. [10_01 Named Agents](10_01_named_agents/README.md) — initial state, independent commits, JSON parity, and shutdown.
2. [10_02 Direct Connections](10_02_direct_connections/README.md) — root → worker → sink → root, output contracts, and explicit emission.
3. [10_03 Local Bus Broadcast](10_03_bus_broadcast/README.md) — declared Bus and counted broadcast.
4. [10_04 Nested Agents](10_04_nested_agents/README.md) — nested ownership and subtree removal.
The IDs follow the recommended reading order.

## Run the section

```sh
mix test.examples examples/10_topologies
```

The [Cell Agent](support/cell.ex) supports member and Bus lessons. The
[shared test assertions](../../test/support/agent_topology_assertions.ex)
observe readiness and shutdown through AgentServer and OTP APIs.

## Limits

Delivery uses best-effort casts and separate commits. A parent snapshot saves
its definition, state, topology intent, and code references. It does not save
the current state of every running member. Tests compare portable snapshots:
module references become captured nested definitions at the storage boundary.
There is no separate Controller, placement engine, graph runtime, distributed
ownership, or coordinated multi-Agent checkpoint.

For child creation selected by a Turn, see
[dynamic child lifecycle](../09_multi_agent/09_01_child_lifecycle/README.md).
Topology declares members and connections as Agent definition data.
