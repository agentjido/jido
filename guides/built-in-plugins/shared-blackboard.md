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
If a write times out or its result Signal does not arrive, read the board
before deciding whether to request another write. The original patch may
already have applied.

## Board lifetime

The board lives in memory on the owner's BEAM node. Stopping the owner
stops the board. A replacement board starts from its initial values and
rejects revisions issued by the previous process. Members resolve the board
by name for each operation. A member restart can therefore read the same
board while the owner stays live.
