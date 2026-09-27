# Plugin-Owned State

A stateful Plugin owns one key in the complete `agent.state` map. The Agent
schema owns the domain fields. The Plugin owns its one declared
field. There is no separate Plugin state map or Agent struct field.

Jido uses `plugin_state` in callback contexts and accessor names for the value
selected from that owned field. This name describes a bounded view, not a
second storage location.

## Declare the Plugin

```elixir
defmodule MyApp.TurnCount do
  use Jido.Plugin

  @impl Jido.Plugin
  def state_spec(_opts) do
    {:turn_count, Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}
  end

  @impl Jido.Plugin
  def reduce(%Jido.Agent.Plugin.Reduction{} = reduction, _opts) do
    {:ok, reduction.plugin_state + 1}
  end
end
```

Declare the package in the Agent DSL:

```elixir
agent do
  schema MyApp.State.schema()
  plugin MyApp.TurnCount
end
```

Jido combines the domain schema and all Plugin-owned field schemas into one
complete state contract.

## Preserve the Existing Value

An Action can read the complete state through `context.agent_state`. It must
preserve every Plugin-owned key in its returned state. Only the owning Agent
Plugin reducer can change its value.

If an Action deletes or replaces a Plugin-owned key, finalization rejects the
candidate. The live Agent keeps its prior state and does not dispatch
Directives.

## Update Before Commit

`reduce/2` runs after executable success and Directive validation. It receives
the prior complete state, the current complete candidate state, its current
owned value, its pure prepared input, and all validated Directives. It returns
only the complete next owned value. Jido validates that value with the owned field
schema. Local values are permitted when that schema accepts them. Portability
is a separate rule for the durable representation.

A failed Turn does not commit the update. A direct command returns the
candidate but does not commit it.

For a live projection, implement `after_commit/3` in the same Plugin module.
It receives only the owned committed value and its matching revision, before
returned Directives. The Action does not need to know about
the runtime. Rebuild from `Init` on startup and replacement; notifications are
not replayed. See [Commit Projection](../examples/09_plugins/09_08_commit_projection/README.md).

## Convert One Owned Value for Persistence

A Plugin can implement `dump/3` and `load/3` when its live owned value needs
a different durable representation. Each callback receives only that owned value,
record-format context, and its mapped static options. Persistence applies the
conversion to the default Agent checkpoint before the final portability check
and record write. On load, it checks stored data before conversion, then
validates the reconstructed local value with the owned field schema
and the complete Agent schema.

A complete custom Agent checkpoint owns its whole payload. Persistence does not
apply Plugin slice conversion to that custom payload.

## Use Outer Defaults

If the owned value is an object that can be absent, put a default on the outer
object. Defaults on nested fields do not create a missing outer object.

## Understand the Trust Boundary

The callback API prevents accidental cross-owner state changes. It is not a
sandbox for untrusted BEAM code.

See [Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md) and
[State Schemas](state-schemas.livemd).
