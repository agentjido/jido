# 11_07 Behavior Tree

Reserve stock with a tree that starts on one Agent Turn and resumes on the
next. Run the same tick pattern with a standalone executor and a tool wrapper.

## What you will learn

- Declare an inline Action and a blackboard condition in the Tree DSL.
- Enable the Behavior Tree Plugin and configure its initial blackboard.
- Resume a running node. Commit an Action result and dispatch its Signal.
- Run a tree without an AgentServer when the caller owns execution.

## Read the code

Start with the [tree and Agent](behavior_tree.ex). Then read the
[live runner](demo.exs) and the [standalone runner](standalone.exs).

## Run it

Run these commands from the Jido repository root.

```sh
mix run examples/11_built_in_capabilities/11_07_behavior_tree/demo.exs
mix run examples/11_built_in_capabilities/11_07_behavior_tree/standalone.exs
mix test.examples examples/11_built_in_capabilities/11_07_behavior_tree --warnings-as-errors
```

Expected live output:

```text
tick=1 status=running reserved=0
tick=2 status=success reserved=3
signal=examples.11.07.stock.reserved reserved=3
```

Expected standalone output:

```text
standalone=running,success ready=true
tool=check_readiness ready=true
```

## Important behavior

The first tick reaches the Wait node and returns `:running`. The second tick
starts with that Wait node, checks `:quantity` on the blackboard, and calls the
inline Reserve Action. The AgentServer commits `:reserved` before it dispatches the
Signal. The reset Signal restores the tree and its blackboard. The stock total
stays at its committed value. The runners stop their processes when they finish.

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
- [Previous example](../11_06_bus_delivery/README.md)
