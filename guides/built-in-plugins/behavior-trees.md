# Run a Behavior Tree in an Agent

Use `Jido.Plugin.BehaviorTree` when a Jido Agent needs to run a tree in steps.
Each tick Signal starts one Turn. A node can return `:running` so the next
tick can resume it.

## Define a tree in the Agent

Use `Jido.BehaviorTree.DSL` after `use Jido.Agent`. One `behavior_tree` block
defines the tree and enables the Plugin. Its options set the initial blackboard
and completion behavior.

```elixir
defmodule Reservations.Agent do
  use Jido.Agent, name: "reservation_agent"
  use Jido.BehaviorTree.DSL

  alias Jido.Joi

  state do
    schema Joi.object(%{
             available_stock: Joi.integer() |> Joi.min(0) |> Joi.default(5),
             reserved: Joi.integer() |> Joi.default(0)
           })
  end

  behavior_tree :reservation, blackboard: %{requested_quantity: 3} do
    sequence :reserve_stock do
      wait :next_tick, milliseconds: 0
      condition :has_stock, state(:available_stock) >= blackboard(:requested_quantity)

      action :reserve,
             [quantity <- blackboard(:requested_quantity), available <- state(:available_stock)],
             inline: [schema: Joi.object(%{quantity: Joi.integer() |> Joi.min(1), available: Joi.integer()})] do
        {:ok, %{reserved: quantity, available_stock: available - quantity}}
      end
    end
  end

  routes do
    signal_source "/reservations"
  end
end
```

| Option | Value |
| --- | --- |
| `:blackboard` | Initial blackboard map. The default is `%{}`. |
| `:reset_on_completion` | If `true`, halt node state after `:success` or `:failure`. Keep the status, tick count, and blackboard. The default is `false`. |

The Plugin owns `agent.state.behavior_tree`. Read `:tree`, `:blackboard`,
`:status`, and `:tick_count` there. Use `Jido.BehaviorTree.Blackboard.get/3`
or `to_map/1` to read blackboard values. Keep configuration, node state, and
blackboard data portable. Send a Signal to change the tree state.

## Conditions and Actions

Use `action :reserve, Reservations.Reserve, params: %{quantity: blackboard(:requested_quantity)}`
to call an existing Action module. Use `action :reserve, [] do ... end` for
an inline Action with no inputs. Inline Actions can call private helpers in
the tree module. Add `context: ctx` to the `inline:` options to bind the
Action context. Use the same return values and Directives as other Actions.

Conditions, Action parameters, and inline bindings use
[Jido expressions](../flows/flow-expressions.md). You can use `state(key)` and
`blackboard(key)` together in any of these positions. Each reference reads a
key from its source when the node runs. `state(key)` reads the current
candidate Agent state, including changes from earlier Actions in the same
tick. Use an Action result to change state.

A condition must return a Boolean. A false condition returns `:failure` and
a selector can try its next child. Unavailable Agent state, missing keys,
and other expression errors fail the tick. A running sequence resumes with
its current child. Put a condition after a Wait to read values when that
Wait finishes.

A tree needs one root. Use distinct names for children of the same parent.
Named nodes add `:node_path` to their telemetry. Use
`node :custom, MyNode.new(...)` to add a node from its constructor. For
standalone execution, give trees that use `state(key)` an Agent or an
`:agent_state` map in the Tick context. The tool wrapper accepts the map
in its execution context.

## Use a shared tree

Use `tree :reservation do ... end` in a separate module to share a tree
or run it standalone. The declaration defines `reservation/0`. In an Agent,
pass the returned tree to the Plugin through `plugins:`.

```elixir
use Jido.Agent,
  name: "reservation_agent",
  plugins: [
    {Jido.Plugin.BehaviorTree,
     %{tree: Reservations.Tree.reservation(), blackboard: %{requested_quantity: 3}}}
  ]
```

You can also pass a `Jido.BehaviorTree.Tree` built with node constructors.
Use one Plugin declaration per Agent.

## Send commands

Start the Agent through `Jido.start_agent/3`, then send a Signal through
`Jido.AgentServer.call/3`. For direct evaluation, pass the same Signal to
the Agent module's `cmd/2` and use the returned Agent for the next call.

| Signal type | Signal data | Effect |
| --- | --- | --- |
| `jido.bt.tick` | `%{}` | Run one traversal. Save the continuation on `:running`. |
| `jido.bt.blackboard.put` | `%{key: :requested_quantity, value: 4}` | Set one value without ticking. |
| `jido.bt.blackboard.merge` | `%{data: %{requested_quantity: 4}}` | Merge values without ticking. |
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
mix run examples/11_built_in_capabilities/11_09_behavior_tree/demo.exs
```

Expected output:

```text
tick=1 status=running reserved=0 available_stock=5
tick=2 status=success reserved=3 available_stock=2
signal=examples.11.09.stock.reserved reserved=3
```

The live example uses an in-memory Agent. An ETS-backed Agent can also
resume a running tree after reactivation in the same VM. The Wait node uses
the VM's monotonic clock, so reset timed nodes before you reuse their state
in another VM.

See [Behavior Tree migration](../reference/behavior-tree-migration.md) for
standalone trees, tool wrappers, and the old Strategy.
