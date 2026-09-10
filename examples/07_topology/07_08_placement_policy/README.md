# 07_08 Placement Policy

Core Topology accepts an exact Erlang node. It does not select a node and does
not rebalance a system. This example keeps that policy in a control Agent and a
Plugin.

## What you will learn

- How lifecycle Signals enter dedicated control-Agent routes.
- How a policy route returns a Plugin-owned Directive.
- How the Plugin calls `Controller.place_agent/4` after Agent state commits.
- Why membership discovery, capacity scoring, and rebalance rules stay outside
  the core Controller.

The example request names a node directly. A real policy can consume membership
Signals and select that node before it returns the same Directive. The target
node must run compatible code and the same named Jido instance. Core does not
fall back to a local node. A disconnected remote result can be uncertain.
The new Agent restores through shared persistence when it is configured.
Without shared persistence, it starts from its declared initial state.

Resources stay separate from placement. Bus is the first core resource, but the
Topology model keeps a general `resources` collection for later resource types.

## Run it

```sh
mix test test/examples/07_topology/07_08_placement_policy --include example --seed 0
```

The example test uses the current node. The core peer test proves real movement
between two Erlang nodes.

Previous: [Lifecycle Signals](../07_07_lifecycle_signals/README.md)
