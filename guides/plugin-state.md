# Plugin-Owned State

A stateful Plugin owns one key in the complete `agent.state` map. The Agent
schema owns the domain fields. The Agent Plugin facet owns its one declared
field. There is no separate Plugin state map or Agent struct field.

Jido uses `plugin_state` in callback contexts and accessor names for the value
selected from that owned field. This name describes a bounded view, not a
second storage location.

## Declare the Facet and Package

```elixir
defmodule MyApp.TurnCount.Agent do
  use Jido.Agent.Plugin

  @impl Jido.Agent.Plugin
  def state_spec(_opts) do
    {:turn_count, Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}
  end

  @impl Jido.Agent.Plugin
  def reduce(%Jido.Agent.Plugin.Reduction{} = reduction, _opts) do
    {:ok, reduction.plugin_state + 1}
  end
end

defmodule MyApp.TurnCount do
  use Jido.Plugin, agent: MyApp.TurnCount.Agent
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
only the complete next owned value. Jido validates that value with the facet
schema and the portable-value rule.

A failed Turn does not commit the update. A direct command returns the
candidate but does not commit it.

## Convert One Owned Value for Persistence

A package can select `Jido.Persistence.Plugin` when its live owned value needs
a different durable representation. The facet receives only that owned value,
record-format context, and its mapped static options. Persistence applies the
conversion to the default Agent checkpoint before it writes the outer record.
On load, it validates the converted value with the paired Agent-facet schema
before Agent restore.

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
