# Plugin-Owned State

A stateful Plugin owns one key in the complete Agent state. The Agent schema
owns domain fields. The Agent Plugin facet owns its one declared value.

## Declare the Facet and Package

```elixir
defmodule MyApp.TurnCount.Agent do
  use Jido.Agent.Plugin
  alias Jido.Agent.Plugin.Contribution

  @impl Jido.Agent.Plugin
  def state_spec(_opts) do
    {:turn_count, Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}
  end

  @impl Jido.Agent.Plugin
  def contribute(transition, _opts) do
    {:ok,
     %Contribution{
       plugin: transition.plugin,
       state: {:replace, transition.plugin_state + 1}
     }}
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

Jido combines the domain schema and all Plugin state schemas into one complete
state contract.

## Preserve the Existing Value

An Action can read Plugin state through `context.agent_state`. It must preserve
that key in its returned state. Only the owning Agent Plugin contribution can
change the value.

If an Action deletes or replaces a Plugin-owned key, finalization rejects the
candidate. The live Agent keeps its prior state and does not dispatch
Directives.

## Contribute Before Commit

`contribute/2` runs after executable success and before complete state
validation. `Jido.Agent.Plugin.Transition` contains the current owned value,
the package's prepared input, declared before and after domain projections,
and Directives owned by the package.

Return `state: :unchanged` to preserve the value. Return
`state: {:replace, complete_owned_state}` to replace it. Jido validates the
replacement with the facet schema and the portable-value rule.

A failed Turn does not commit the contribution. A direct command returns the
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

The callback API prevents accidental cross-owner data use. It is not a sandbox
for untrusted BEAM code. An Agent facet receives only its declared projection,
but code in the same VM still has normal Elixir and Erlang capabilities.

See [Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md) and
[State Schemas](state-schemas.livemd).
