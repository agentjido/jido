# Plugin-Owned State

A stateful Plugin owns one key in the complete Agent state. The Agent schema
owns domain fields. The Plugin schema owns its one declared value.

## Declare The Key

```elixir
defmodule MyApp.TurnCount do
  use Jido.Plugin

  @impl Jido.Plugin
  def state_spec(_opts) do
    {:turn_count, Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}
  end

  @impl Jido.Plugin
  def update_state(count, _directives, _opts) do
    {:ok, count + 1}
  end
end
```

Declare it in the Agent DSL:

```elixir
agent do
  schema MyApp.State.schema()
  plugin MyApp.TurnCount
end
```

Jido combines the domain schema and all Plugin state schemas into one complete
state contract.

## Preserve The Existing Value

An Action can read Plugin state through `context.agent_state`. It must preserve
that key in its returned state. Only the owning Plugin update stage can change
the value.

If an Action deletes or replaces a Plugin-owned key, finalization rejects the
candidate. The live Agent keeps its prior state and does not dispatch
Directives.

## Update Before Commit

`update_state/3` runs after executable success and before complete state
validation. It gets the current owned value, the Directive list, and Plugin
options. A successful update is part of the same Agent candidate and commit.

A failed Turn does not commit the Plugin update. A direct command returns the
updated candidate but still does not commit it.

## Use Outer Defaults

If the owned value is an object that can be absent, put a default on the outer
object. Defaults on nested fields do not create a missing outer object.

## Understand The Trust Boundary

Plugin state ownership prevents accidental writes during Agent finalization. It
is not a read-security boundary. Plugins can inspect command data, and Agent
executables can read complete state.

See [Plugin Contract And Lifecycle](plugin-contract-and-lifecycle.md) and
[State Schemas](state-schemas.livemd).
