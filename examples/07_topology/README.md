# Topology examples

These examples define and activate complete Agent systems. Construction
and planning start no process. A Controller owns activation, repair, inspection,
and cleanup.

## Learning order

1. [Independent Agents](07_01_independent/README.md) — start unrelated singleton Agents and request repair.
2. [Owned Hierarchy](07_02_hierarchy/README.md) — declare direct parent and child relationships.
3. [Bus Swarm](07_03_bus_swarm/README.md) — define the same 1,000-worker system with DSL, Builder, and JSON.
4. [Keyed Accounts](07_04_keyed_accounts/README.md) — derive stable group identity from input records.
5. [Composed System](07_05_composed_system/README.md) — include reusable Topologies with imports, bindings, and exports.
6. [Plugin Contribution](07_06_plugin_contribution/README.md) — let an Agent Plugin add static topology wiring.
7. [Lifecycle Signals](07_07_lifecycle_signals/README.md) — connect an optional control Agent through normal routes.
8. [Placement Policy](07_08_placement_policy/README.md) — keep node selection in a Plugin and use the exact-node core mechanism.

## Run the section

```sh
mix test test/examples/07_topology --include example --seed 0
```

Expected result: each planned system starts, proves its declared relationships
or delivery behavior, and cleans its local resources.

## Shared support

The [Cell Agent](support/cell.ex) is the small shared worker used throughout the
section.

## Limits

The Controller repairs one target and can place an Agent on an exact Erlang
node. It does not discover nodes, select capacity policy, rebalance a system,
or provide distributed authority.
