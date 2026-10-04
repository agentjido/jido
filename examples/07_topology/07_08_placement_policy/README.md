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

## Read the code

Read [the control Agent and static placement](placement_policy.ex),
[the Directive](move.ex), [the Plugin](placement_plugin.ex), and the
[example test](../../../test/examples/07_topology/07_08_placement_policy/placement_policy_test.exs).
The [core peer test](../../../test/jido/topology/controller_placement_test.exs)
proves placement and replacement across two Erlang nodes.

## Run it

```sh
mix test test/examples/07_topology/07_08_placement_policy --include example --seed 0
```

Expected result: the static declaration places both workers on the current
node. Repeating exact placement on that node preserves the worker PID.
Controller shutdown removes both workers and leaves the application-owned
control Agent alive. The application then stops the control Agent and its
Plugin processes.

## Important behavior

The example request names a node directly. A real policy can consume membership
Signals and select that node before it returns the same Directive. The target
node must run compatible code and the same named Jido instance. Core does not
fall back to a local node. A disconnected remote result can be uncertain.
The new Agent restores through shared persistence when it is configured.
Without shared persistence, it starts from its declared initial state.

Resources stay separate from placement. Bus is the first core resource, but the
Topology model keeps a general `resources` collection for later resource types.

## Limits

This example does not discover nodes, score capacity, or rebalance Agents. The
local example test does not prove a cross-node move; the linked peer test does.

## Files

- [Control Agent and Topology](placement_policy.ex)
- [Directive](move.ex)
- [Plugin](placement_plugin.ex)
- [Example tests](../../../test/examples/07_topology/07_08_placement_policy/placement_policy_test.exs)
- [Core peer test](../../../test/jido/topology/controller_placement_test.exs)

Previous: [Lifecycle Signals](../07_07_lifecycle_signals/README.md) | Next: [Additive Update](../07_09_additive_update/README.md)
