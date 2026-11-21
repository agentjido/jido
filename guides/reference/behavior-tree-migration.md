# Move Behavior Trees to Jido v3

Use this guide when moving from the separate `jido_behaviortree` package to a
Jido v3 release that includes `Jido.Plugin.BehaviorTree`.

## Update the dependency and the Agent together

Remove `:jido_behaviortree` and select the Jido v3 version that contains the
Plugin in the same dependency update. Remove transitive references to the old
package and check `mix deps.tree`. Both packages define `Jido.BehaviorTree`
modules. A mixed dependency tree can load the wrong BEAM module. The old
package also declares a Jido v2 dependency.

Move an Agent from `strategy: {Jido.Agent.Strategy.BehaviorTree, opts}` to
`plugins: [{Jido.Plugin.BehaviorTree, %{tree: tree, blackboard: initial}}]`.
An Elixir module can call a tree builder when it declares its Agent.
For a tree that belongs to one Agent, use the
[`behavior_tree` block](../built-in-plugins/behavior-trees.md#define-a-tree-in-the-agent)
to define the tree and enable the Plugin in the same module. A v2
`:tree_builder` that takes an Agent instance needs an application-specific
change. Define a static tree and pass per-instance data through the blackboard
Signals. Tree structs in Plugin configuration use the Elixir authoring path.
The standard JSON Agent document codec does not encode those structs.

| v2 entry point | v3 path |
| --- | --- |
| `cmd/3` with a v2 Strategy instruction | Send the equivalent `jido.bt.*` Signal. |
| Instructions injected into a tick | Put the input on the blackboard before ticking. |
| Strategy snapshot | Read `state.behavior_tree` on the returned Agent or live snapshot. |
| `Jido.Agent.StateOp` from a leaf | Return a plain result map for Agent state updates and a list of v3 Directives for runtime work. |
| Custom `tick/2` and `halt/1` | Keep the callbacks. Use optional `tick_with_context/2` to return blackboard changes or Directives. Custom parent nodes must halt their children. |

The five Signal types keep their names. A tick now takes empty data. For
custom nodes, the Plugin exposes current Agent state through
`tick.context.agent_state`. The standalone executor can still supply a
`Jido.Agent` value in `tick.agent`. Use [Run a Behavior Tree in an Agent](../built-in-plugins/behavior-trees.md)
for the command data and examples.

Start the v3 Agent with its configured initial tree. If your application
needs old blackboard data, copy the required values with a merge Signal.
Restoring a v2 Strategy snapshot or resuming a timed Wait across VM restarts
requires a separate migration.

## Standalone executor

Use `Jido.BehaviorTree.Agent.start_link/1` or
`Jido.BehaviorTree.start_agent/1` for manual or interval-based ticks in a
local GenServer. This path has no AgentServer Turn. Use
`Jido.BehaviorTree.Agent.directives/1` to read the latest batch. The caller
owns handling those requests. With `:jido_agent`, plain Action result maps
update the executor's in-memory copy of the Agent. This path has no Agent
schema validation or commit. Use the Plugin for those guarantees.

For an immutable tree, use `Tree.tick_with_context/2` to get the updated
tree and Tick. Use this form when you need the blackboard or Directives
from the traversal.

## Tool wrapper

Use `Jido.BehaviorTree.Skill.new/4` and `Skill.to_tool/1` for a tool
definition. Replace old keyword schemas with `Jido.Joi.object/1` schemas.
`Skill.run/3` validates input, seeds the blackboard, and returns the final
blackboard through the output schema. Use trees that produce data only.
The wrapper rejects Directives. Its timeout is checked between ticks, so
node callbacks must return promptly.

Run the standalone executor and tool wrapper from the core repository:

```sh
mix run examples/11_built_in_capabilities/11_07_behavior_tree/standalone.exs
```

For node telemetry, attach to the established `[:jido, :bt, :node, ...]`
events. Status is in stop metadata. To use the optional logging handler,
start `Jido.BehaviorTree.Telemetry` under your supervisor and configure
`:jido, :behavior_tree_telemetry`.
