# 07_01 Independent Agents

A Topology starts two unrelated Agents with separate state and identity.

## What you will learn

- How a declarative Topology defines singleton Agents.
- How manual repair replaces one missing Agent without replacing an unchanged peer.

## Read the code

Read [the Topology](independent.ex), then the shared [Cell Agent](../support/cell.ex).

## Run it

```sh
mix test test/examples/07_topology/07_01_independent --include example --seed 0
```

Expected result: both Agents start, state changes stay isolated, and an explicit
repair recreates only the missing Agent.

## Important behavior

Manual repair waits for `Controller.reconcile/1`. The Controller keeps the
committed state and PID of a member that is still valid.

## Limits

This example has no ownership relationship or shared resource.

## Files

- [Source](independent.ex)
- [Tests](../../../test/examples/07_topology/07_01_independent/independent_test.exs)
- [Cell Agent](../support/cell.ex)

Previous: [Flow Factory](../../06_factory/06_04_flow_factory/README.md) | Next: [Owned Hierarchy](../07_02_hierarchy/README.md)
