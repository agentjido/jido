---
modules:
  - Jido.BehaviorTree
  - Jido.BehaviorTree.Agent
  - Jido.BehaviorTree.Blackboard
  - Jido.BehaviorTree.DSL
  - Jido.BehaviorTree.Error
  - Jido.BehaviorTree.Expression
  - Jido.BehaviorTree.Expression.Reference
  - Jido.BehaviorTree.Node
  - Jido.BehaviorTree.Nodes.Action
  - Jido.BehaviorTree.Nodes.Condition
  - Jido.BehaviorTree.Nodes.Failer
  - Jido.BehaviorTree.Nodes.Inverter
  - Jido.BehaviorTree.Nodes.Named
  - Jido.BehaviorTree.Nodes.Repeat
  - Jido.BehaviorTree.Nodes.Selector
  - Jido.BehaviorTree.Nodes.Sequence
  - Jido.BehaviorTree.Nodes.SetBlackboard
  - Jido.BehaviorTree.Nodes.Succeeder
  - Jido.BehaviorTree.Nodes.Wait
  - Jido.BehaviorTree.Skill
  - Jido.BehaviorTree.Status
  - Jido.BehaviorTree.Telemetry
  - Jido.BehaviorTree.Tick
  - Jido.BehaviorTree.Tree
  - Jido.Plugin.BehaviorTree
  - Jido.Plugin.BehaviorTree.Command
  - Jido.Plugin.BehaviorTree.StateUpdate
---

## Purpose

Run Behavior Trees as an opt-in capability. The component owns traversal,
continuation, tree commands, and the standalone entry points. Core owns Turn
validation, commit, and runtime dispatch.

## Obligations

### jido.plugin.behavior_tree.I1 — Opt-in configuration

- **scope:** `Jido.Plugin.BehaviorTree.normalize/1`, `Jido.Plugin.BehaviorTree.derive_routes/1`
- **must:** Contribute the five tree routes only for configured Agents. Reject a missing tree, malformed nested nodes, invalid options, and runtime-only values.
- **kind:** functional
- **status:** active

### jido.plugin.behavior_tree.I2 — Continuation and Action effects

- **scope:** `Jido.Plugin.BehaviorTree.Command.run/2`, `Jido.BehaviorTree.Nodes.Action.tick_with_context/2`
- **must:** Run a single traversal, resume the running child, keep blackboard writes, and pass each successful leaf's Action result and Directives in order.
- **kind:** ordering
- **status:** active

### jido.plugin.behavior_tree.I3 — Explicit control

- **scope:** `Jido.Plugin.BehaviorTree.Command.run/2`
- **must:** Put and merge data without ticking. Halt the tree and keep the blackboard. Reset to the configured tree and blackboard. Optionally halt on terminal status.
- **kind:** functional
- **status:** active

### jido.plugin.behavior_tree.I4 — Failed ticks and state ownership

- **scope:** `Jido.Plugin.BehaviorTree.Command.run/2`, `Jido.Plugin.BehaviorTree.StateUpdate.validate/1`
- **must:** Reject invalid input, nonportable tree state, and Action result changes to Plugin-owned state. A node error fails the Turn and discards results and Directives from that tick.
- **kind:** functional
- **status:** active

### jido.plugin.behavior_tree.I5 — Tree authoring

- **scope:** `Jido.BehaviorTree.DSL.behavior_tree/3`, `Jido.BehaviorTree.DSL.tree/2`, `Jido.BehaviorTree.Expression.evaluate/2`, `Jido.BehaviorTree.Nodes.Condition.tick/2`
- **must:** An inline Agent block enables one Plugin with the declared tree and options. Reject duplicate Plugin declarations. Compile inline leaves to regular Actions. Evaluate declared conditions and Action inputs with the current blackboard and candidate Agent state. Reject unsupported expression syntax and fail a tick when a required input or its state is unavailable.
- **kind:** functional
- **status:** active
