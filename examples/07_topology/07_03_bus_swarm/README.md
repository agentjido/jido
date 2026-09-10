# 07_03 Bus Swarm

A Controller starts one coordinator, 1,000 worker Agents, and one Bus from a
stored Topology definition.

## What you will learn

- How DSL, Builder, and trusted JSON Codec forms define the same Topology.
- How one Bus subscription expands across a large Agent group.

## Read the code

Read [the DSL Topology](swarm.ex), [the Builder and Codec forms](formats.ex),
the [JSON fixture](fixtures/swarm.json), then the shared [Cell Agent](../support/cell.ex).

## Run it

```sh
mix test test/examples/07_topology/07_03_bus_swarm --include example --seed 0
```

Expected result: 1,001 Agents start, all workers commit one broadcast value,
and Controller shutdown removes every worker.

## Important behavior

Bus broadcast gives each matching subscriber the Signal. It is not a work queue.
Startup concurrency and Agent execution capacity are separate limits.

## Limits

The scale result is local and in memory. It is not a multi-host throughput claim.

## Files

- [DSL](swarm.ex)
- [Builder and Codec](formats.ex)
- [JSON fixture](fixtures/swarm.json)
- [Tests](../../../test/examples/07_topology/07_03_bus_swarm/bus_swarm_test.exs)
- [Cell Agent](../support/cell.ex)

Previous: [Owned Hierarchy](../07_02_hierarchy/README.md) | Next: [Keyed Accounts](../07_04_keyed_accounts/README.md)
