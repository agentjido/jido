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
three workers. When the leader fails, OTP restarts it and the workers stop.
Manual repair binds the replacement leader to the coordinator and leaves the
workers stopped. Controller shutdown removes the remaining Agents.

## Important behavior

Ownership creates activation dependencies and logical parent bindings. All
local Agents are OTP siblings. Each Agent owns only its direct logical
children. `on_parent_exit: :stop` causes a clean worker shutdown. Transient
workers then stay stopped, even if OTP restarts the leader. Select `:continue`
when workers must stay alive until their parent binding is repaired.

## Limits

This example does not use a Bus or show automatic repair.

## Files

- [Source](hierarchy.ex)
- [Tests](../../../test/examples/07_topology/07_02_hierarchy/hierarchy_test.exs)
- [Cell Agent](../support/cell.ex)

Previous: [Independent Agents](../07_01_independent/README.md) | Next: [Bus Swarm](../07_03_bus_swarm/README.md)
