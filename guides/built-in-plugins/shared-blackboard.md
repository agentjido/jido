# Share current facts on a blackboard

Start with the inventory example. A counter posts 12 items for bin A. A
second counter reads 12. The example also shows how a Statechart handles
a patch result. [Run the inventory example](../../examples/11_built_in_capabilities/11_11_shared_blackboard/README.md).

## Set up the board

Add the Server Plugin to an Agent in your Jido instance. Use a different
board name for each owner in that instance.

```elixir
plugins: [
  {Jido.Plugin.Blackboard.Server, %{name: "inventory", initial: %{"bin-a" => 0}}}
]
```

Add the Client Plugin to a member in the same instance. Configure the
Signal paths that need current board data.

```elixir
plugins: [
  {Jido.Plugin.Blackboard.Client, %{name: "inventory", read_on: ["inventory.read"]}}
]
```

A matching Turn gets a snapshot at
`context.plugin_inputs[Jido.Plugin.Blackboard.Client].runtime`.
The snapshot contains `values` and an opaque `revision`. A failed read
stops admission. The result Signal skips this automatic read, so an agent
can handle a board failure while the board is unavailable. Direct Agent
commands can use an explicit snapshot in their Signal data.

## Write after the turn commits

Return a `Jido.Plugin.Blackboard.Client.Patch` Directive from the handler.
Set its `revision` from the snapshot, give the request a unique
`request_id`, and supply `put` values or `delete` keys. Use string keys
and portable values. The board advances its revision for each accepted
patch, including a patch that leaves the same values.

The client attempts the patch after the turn commits. Add a route for
`jido.blackboard.patch.result` and match the `"request_id"` before using
the result. The Signal data includes `"board"` and `"status"`.
A successful write has status `"ok"` and includes the new `"revision"`.
A conflict leaves the board unchanged. The public board API and Client
Plugin default to a 500 ms request timeout. Configure the Client's `timeout`
in milliseconds when needed, within the Agent's turn and effect budgets.

Outside a turn, use `Jido.Blackboard.read(instance, name)` and
`Jido.Blackboard.patch(instance, name, revision, puts, deletes)`.
If a write times out, reports `"indeterminate"`, or has no result Signal,
read the board before deciding whether to request another write. The patch
may already have applied.

## Board lifetime

The owner serves the board on its BEAM node. A board name identifies one
live owner in each Jido instance. Stopping the owner stops the board.
Members resolve the name for each operation and can read the board again
when an owner reopens it.

Use one small owner Agent per work item when agents publish independent
results. Agents that share a board also share its revision. Use one board
when a decision depends on several keys together. The example uses
`Jido.Agent.define!/1` to give each owner a name chosen at runtime.

## Keep values across owner restarts

Add `persistence: :inherit` to the Server Plugin configuration:

```elixir
plugins: [
  {Jido.Plugin.Blackboard.Server,
   %{name: "inventory", initial: %{"bin-a" => 0}, persistence: :inherit}}
]
```

Configure a stable namespace and a persistence profile on the Jido instance.
Each board record uses the owner's stable Agent Address and the board name.
The board uses the instance Store and codec. It serves reads from memory and
writes the complete record with an atomic condition before reporting success.
An indeterminate write clears the cached snapshot. The next read reloads it
from the Store. [Persistence adapters](../reference/persistence-adapter-matrix.md).

1. Use `Jido.create_agent/4` and `Jido.activate_agent/3` to create and open a
   durable owner.
2. Use `Jido.stop_agent/3` to take its board offline. Activate the same
   Address again to restore its saved values and issue a fresh revision.
3. Use `Jido.Blackboard.delete(instance, address, name)` after stopping the
   owner to retire the saved board. A tombstone prevents that owner Address
   from reopening the same board. Delete the stopped Agent record separately
   if the application also wants to retire the Agent.

A board without `persistence: :inherit` starts with its configured initial
values after each owner restart. Every new board process rejects revisions
issued by earlier processes.
