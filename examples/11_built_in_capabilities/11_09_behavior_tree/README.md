# 11_09 Behavior Tree

Reserve stock with a tree that starts on one Agent Turn and resumes on the
next. Run the same tick pattern with a standalone executor and a tool wrapper.

## What you will learn

- Define a tree in the Agent with a `behavior_tree` block that enables the Plugin.
- Read the requested quantity from the blackboard and available stock from Agent state.
- Resume a running node. Commit an Action result and dispatch its Signal.
- Run a tree without an AgentServer when the caller owns execution.

## Read the code

Start with the [tree and Agent](behavior_tree.ex). Then read the
[live runner](demo.exs) and the [standalone runner](standalone.exs).

## Run it

Run these commands from the Jido repository root.

```sh
mix run examples/11_built_in_capabilities/11_09_behavior_tree/demo.exs
mix run examples/11_built_in_capabilities/11_09_behavior_tree/standalone.exs
mix test.examples examples/11_built_in_capabilities/11_09_behavior_tree --warnings-as-errors
```

Expected live output:

```text
tick=1 status=running reserved=0 available_stock=5
tick=2 status=success reserved=3 available_stock=2
signal=examples.11.09.stock.reserved reserved=3
```

Expected standalone output:

```text
standalone=running,success ready=true
tool=check_readiness ready=true
```

## Important behavior

The first tick reaches the Wait node and returns `:running`. The second tick
resumes at that Wait node. The condition compares `:available_stock` in Agent
state with `:requested_quantity` on the blackboard. The inline Reserve Action
returns the updated stock and reservation values. The AgentServer commits both
values before it dispatches the Signal. The reset Signal restores the tree and
blackboard. Stock and reservations stay at their committed values. The runners
stop their processes when they finish.

## Limits

The examples run offline in memory. The Wait node needs another tick to
resume. The standalone tool rejects Directives.

## Core Fit and Gaps

The Plugin routes use the same Turn and Directive rules as application
Actions. The example uses a zero-duration Wait so that the second tick always
completes it. An application that needs periodic ticks can use the Timer
Plugin or send tick Signals from its own scheduler.

## Files

- [Tree and Agent](behavior_tree.ex)
- [Live runner](demo.exs)
- [Standalone runner](standalone.exs)
- [Integration test](behavior_tree_test.exs)
- [Previous example](../11_08_statechart_plugin/README.md)
