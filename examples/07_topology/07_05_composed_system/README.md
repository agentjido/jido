# 07_05 Composed System

A root Topology includes two reusable worker teams that share one root-owned Bus
through explicit imports, bindings, and exports.

## What you will learn

- How an included Topology exposes public Agents, groups, and Buses.
- How component paths isolate identity while one Controller applies root limits.

## Read the code

Read [the root Topology](composed_system.ex), [the reusable team](worker_team.ex),
[the Builder and Codec forms](formats.ex), and the
[JSON fixture](fixtures/composed_system.json).

## Run it

```sh
mix test test/examples/07_topology/07_05_composed_system --include example --seed 0
```

Expected result: two teams start with one shared Bus, all five workers receive
the broadcast, direct team state stays isolated, and shutdown removes all
Agents and the Bus.

## Important behavior

An import must have an explicit binding. An export is the public boundary for
an included component. Inclusion alone does not create Agent ownership.

## Limits

One Controller owns the complete static plan. Live component replacement and
per-component pause are not supported.

## Files

- [Root Topology](composed_system.ex)
- [Reusable team](worker_team.ex)
- [Builder and Codec](formats.ex)
- [JSON fixture](fixtures/composed_system.json)
- [Tests](../../../test/examples/07_topology/07_05_composed_system/composed_system_test.exs)
- [Cell Agent](../support/cell.ex)

Previous: [Keyed Accounts](../07_04_keyed_accounts/README.md) | Next: [Plugin Contribution](../07_06_plugin_contribution/README.md)
