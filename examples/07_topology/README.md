# Topology examples

A normal Agent definition contains named members and output connections.
AgentServer applies that definition under its OTP supervisor. Pure Agent
construction starts no processes.

## Learning order

- `01` [Named Members](07_01_independent/README.md) — separate initial state, commands, and owner shutdown.
- `02` [Nested Agents](07_02_hierarchy/README.md) — reusable definitions and subtree removal.
- `03` [Local Bus Broadcast](07_03_bus_swarm/README.md) — a declared Bus and explicit counted delivery.
- `09` [Topology Mutations](07_09_topology_mutations/README.md) — add, resize, replace, and remove members.

The retained example IDs stay stable.

## Run the section

```sh
mix test test/examples/07_topology --include example --seed 0
```

Expected result: each local system starts, proves its member state or delivery
behavior, and stops its owned runtime tree.

## Shared support

The [Cell Agent](support/cell.ex) records received work. The
[test assertions](../../test/examples/support/agent_topology_assertions.ex)
start ready Agents and monitor shutdown through public AgentServer and OTP APIs.

## Limits

These examples use local runtime support. They do not define a separate
Controller, placement policy, keyed expansion, or imports and exports.
A parent snapshot captures its own state and topology intent, not the current
state of every running member.
