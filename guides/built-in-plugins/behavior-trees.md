# Run a Behavior Tree in an Agent

Use `Jido.Plugin.BehaviorTree` when a Jido Agent needs to run a tree in steps.
Each tick Signal starts one Turn. A node can return `:running` so the next
tick can resume it.

## Configure the Plugin

Pass the Plugin and its configuration map in the Agent declaration. Define
the Action modules referenced by the tree before you run the Agent.

```elixir
defmodule Reservations.Agent do
  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Action, Sequence, Wait}
  alias Jido.Joi

  use Jido.Agent,
    name: "reservation_agent",
    plugins: [
      {Jido.Plugin.BehaviorTree,
       %{
         tree:
           Tree.new(
             Sequence.new([
               Wait.new(0),
               Action.new(Reservations.Reserve, %{quantity: {:from_blackboard, :quantity}})
             ])
           ),
         blackboard: %{quantity: 3}
       }}
    ]

  state do
    schema Joi.object(%{reserved: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/reservations"
  end
end
```

| Option | Value |
| --- | --- |
| `:tree` | Required `Jido.BehaviorTree.Tree` with a root node. |
| `:blackboard` | Initial blackboard map. The default is `%{}`. |
| `:reset_on_completion` | If `true`, halt node state after `:success` or `:failure`. Keep the status, tick count, and blackboard. The default is `false`. |

The Plugin owns `agent.state.behavior_tree`. Read `:tree`, `:blackboard`,
`:status`, and `:tick_count` there. Use `Jido.BehaviorTree.Blackboard.get/3`
or `to_map/1` to read blackboard values. Keep configuration, node state, and
blackboard data portable. Send a Signal to change the tree state.

## Declare a tree in Elixir

Use `Jido.BehaviorTree.DSL` in a module. The `tree :reservation` declaration
defines `reservation/0`. Pass the returned tree to the Plugin as
`%{tree: Reservations.Tree.reservation(), blackboard: %{quantity: 3}}`.

```elixir
defmodule Reservations.Tree do
  use Jido.BehaviorTree.DSL

  alias Jido.Joi

  tree :reservation do
    sequence :reserve_stock do
      wait :next_tick, milliseconds: 0
      condition :has_stock, blackboard(:quantity) > 0

      action :reserve, quantity <- blackboard(:quantity),
        inline: [schema: Joi.object(%{quantity: Joi.integer() |> Joi.min(1)})] do
        {:ok, %{reserved: quantity}}
      end
    end
  end
end
```

Use `action :reserve, Reservations.Reserve, params: %{quantity: blackboard(:quantity)}`
to call an existing Action module. Use `action :reserve, [] do ... end` for
an inline Action with no inputs. Inline Actions can call private helpers in
the tree module. Add `context: ctx` to the `inline:` options to bind the
Action context. Use the same return values and Directives as other Actions.

Conditions, Action parameters, and inline bindings use
[Jido expressions](../flows/flow-expressions.md). A condition must return a
Boolean. A false condition returns `:failure` and a selector can try its next
child. A missing blackboard key or an expression error fails the tick. A
running sequence resumes with its current child. Put a condition after a
Wait if it must read values when that Wait finishes.

A tree needs one root. Use distinct names for children of the same parent.
Named nodes add `:node_path` to their telemetry. Use
`node :custom, MyNode.new(...)` to add a node from its constructor. The same
tree works with the standalone executor and tool wrapper.

## Send commands

Start the Agent through `Jido.start_agent/3`, then send a Signal through
`Jido.AgentServer.call/3`. For direct evaluation, pass the same Signal to
the Agent module's `cmd/2` and use the returned Agent for the next call.

| Signal type | Signal data | Effect |
| --- | --- | --- |
| `jido.bt.tick` | `%{}` | Run one traversal. Save the continuation on `:running`. |
| `jido.bt.blackboard.put` | `%{key: :quantity, value: 4}` | Set one value without ticking. |
| `jido.bt.blackboard.merge` | `%{data: %{quantity: 4}}` | Merge values without ticking. |
| `jido.bt.halt` | `%{}` | Halt the nodes and set status to `:idle`. Keep the blackboard and tick count. |
| `jido.bt.reset` | `%{}` | Halt the current tree. Restore the configured tree and blackboard, set status to `:idle`, and set the count to zero. |

The contributed routes generate helpers such as `Reservations.Agent.bt_tick_signal!()`
when the Agent has a Signal source. To tick periodically, schedule tick
Signals with the [Timer Plugin](timers.livemd). The Wait node checks elapsed
time on a subsequent tick. It does not schedule the tick.

## Apply Action results and Directives

The Action node uses `Jido.Exec` to validate input and output. A parameter
such as `{:from_blackboard, :quantity}` reads from the current blackboard.
Each successful Action writes its output to the node and to
`:last_result` on the blackboard.

In a Plugin Turn, a plain map output updates candidate Agent state by key.
Later nodes see the changed state through `context.agent_state`. Use the
Agent state schema to declare the keys that a leaf can update. A portable
`Jido.Action.Output.raw/1` envelope records a result without updating Agent
state. Leave all Plugin-owned fields intact.

An Action may return `{:ok, result, directives}`. On a live Agent,
AgentServer validates the batch and commits before dispatch. Direct
evaluation returns the batch to the caller. The batch includes one internal
tree-state Directive, which counts toward the AgentServer Directive limit. A node error fails the Turn and discards its
candidate state and Directives. A tree `:failure` is a normal tree status
and can commit. Keep pre-commit work free of irreversible I/O when you need
failed ticks to leave external systems unchanged.

## Run the examples

From the Jido repository root, run:

```sh
mix run examples/11_built_in_capabilities/11_07_behavior_tree/demo.exs
```

Expected output:

```text
tick=1 status=running reserved=0
tick=2 status=success reserved=3
signal=examples.11.07.stock.reserved reserved=3
```

The live example uses an in-memory Agent. An ETS-backed Agent can also
resume a running tree after reactivation in the same VM. The Wait node uses
the VM's monotonic clock, so reset timed nodes before you reuse their state
in another VM.

See [Behavior Tree migration](../reference/behavior-tree-migration.md) for
standalone trees, tool wrappers, and the old Strategy.
