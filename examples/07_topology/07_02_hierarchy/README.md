# 07_02 Owned Hierarchy

A Topology declares a coordinator, its leader, and three workers owned by that
leader.

## What you will learn

- How `owns` creates direct Agent ownership relationships.
- How a group expands into stable child members.

## Read the code

Read [the Topology](hierarchy.ex), then the shared [Cell Agent](../support/cell.ex).

## Run it

```sh
mix test test/examples/07_topology/07_02_hierarchy --include example --seed 0
```

Expected result: the Controller starts five Agents and the leader owns exactly
three workers.

## Important behavior

Ownership creates startup dependencies and cleanup order. Each Agent owns only
its direct children.

## Limits

This example does not use a Bus or show automatic repair.

## Files

- [Source](hierarchy.ex)
- [Tests](../../../test/examples/07_topology/07_02_hierarchy/hierarchy_test.exs)
- [Cell Agent](../support/cell.ex)

Previous: [Independent Agents](../07_01_independent/README.md) | Next: [Bus Swarm](../07_03_bus_swarm/README.md)
