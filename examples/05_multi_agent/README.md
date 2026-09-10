# Multi-agent examples

These examples move from local child ownership to explicit remote placement
and node-loss observation. Each Agent owns only its direct children.

## Learning order

1. [Child Lifecycle](05_01_child_lifecycle/README.md) — start, restart, and stop an owned child.
2. [Correlated Requests](05_02_correlated_requests/README.md) — match a child result to one pending request.
3. [Agent Hierarchy](05_03_agent_hierarchy/README.md) — form and clean up a tree through direct ownership.
4. [Remote Child](05_04_remote_child/README.md) — place an owned child on a selected Erlang node.
5. [Remote Lifecycle](05_05_remote_lifecycle/README.md) — distinguish observed exit from lost connectivity.

## Run the section

```sh
mix test test/examples/05_multi_agent --include example --seed 0
```

Expected result: the local and two-node behavior tests pass without network
services or credentials.

Run the optional two-node demonstration:

```sh
mix run examples/05_multi_agent/05_04_remote_child/demo.exs
```

## Shared support

- [Worker Agent](support/worker.ex) doubles work for the child lifecycle and correlated request examples.
- [Keep State Action](../support/keep_state.ex) handles lifecycle Signals that do not change domain state.

## Limits

These examples do not provide a cluster-wide ownership lease or an application
worker pool. See the [distributed authority research item](../99_research/99_02_distributed_authority/README.md)
for the unsupported ownership contract.
