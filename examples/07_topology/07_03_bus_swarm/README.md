# 07_03 Local Bus Broadcast

One declared local Bus broadcasts work outputs to three counted members.

## What you will learn

- How `Jido.Plugin.Bus.DSL` contributes an explicit local Bus.
- How connections carry root outputs through the Bus to members.
- Why a counted destination requires `delivery: :broadcast`.

## Read the code

Read the root Agent and its connections, then the Cell Agent and tests.

## Run it

```sh
mix test test/examples/07_topology/07_03_bus_swarm --include example --seed 0
```

Expected result: One root command commits and emits a work Signal. Each of the three members
commits its own Turn and records the value. Owner shutdown stops the owned
supervisor tree.

## Important behavior

The count binds from root state at startup. A root command is selected by its
route; its emitted Signal follows the declared output connections. The root
reply confirms its own commit. The tests wait separately for member commits.

The Bus runtime belongs to the AgentServer supervisor. The cleanup test
monitors that supervisor and its supervised descendants through public OTP APIs.

## Limits

Delivery uses best-effort casts. This example does not promise durable
delivery, acknowledgements, or atomic changes across all members. It is a
small behavior example, not a 1,000-worker capacity test.

## Files

- [Source](swarm.ex)
- [Cell Agent](../support/cell.ex)
- [Tests](../../../test/examples/07_topology/07_03_bus_swarm/bus_swarm_test.exs)
- [Test runtime assertions](../../../test/examples/support/agent_topology_assertions.ex)

Previous: [Nested Agents](../07_02_hierarchy/README.md) | Next: [Topology Mutations](../07_09_topology_mutations/README.md)

This is also the fixed-group lesson: the Agent declares stable worker roles
and the Bus routes work. A separate controller membership table is not needed.
