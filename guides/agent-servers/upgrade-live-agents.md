# Upgrade a Running Agent

Use `Jido.AgentServer.upgrade/3` to replace one complete Agent definition. This
is an administrative operation. A normal Agent command can change state and
return runtime Directives, but it cannot change routes, Plugins, or topology.

## Build the replacement

Encode a complete neutral Agent definition with `Jido.Agent.Codec`. Use an
explicit `Jido.Catalog` that contains every code and schema reference in the
document.

```elixir
definition = MyApp.OrderAgentV2.definition()
catalog = MyApp.JidoCatalog.load!()

{:ok, document} =
  Jido.Codec.encode(definition,
    catalog: catalog,
    codec: Jido.Agent.Codec
  )
```

The document is the full replacement. It is not a patch.

## Migrate the state

When the state schema changes, pass an Action or Flow through `migrate:`. It
receives `%{state: old_state}` and must return the complete new state. It must
not return Directives.

```elixir
defmodule MyApp.MigrateOrderState do
  use Jido.Action,
    name: "migrate_order_state_v2",
    schema: Jido.Joi.object(%{state: Jido.Joi.map()})

  def run(%{state: old}, _context) do
    {:ok, %{items: old.items, status: :open}}
  end
end
```

Then request the upgrade:

```elixir
{:ok, upgraded, []} =
  Jido.AgentServer.upgrade(server, document,
    catalog: catalog,
    migrate: MyApp.MigrateOrderState
  )
```

## Runtime rules

- The AgentServer must be supervised and idle.
- Busy work returns `{:error, :agent_busy}`. The request does not wait in the
  command queue.
- Jido validates the complete definition and state before it accepts them.
- Persistence uses revision control before the activation changes.
- The activation restarts under the same stable `Jido.Agent.Ref`.
- The AgentServer PID can change.
- Jido does not migrate an active durable Flow.

Use the stable Ref for later calls. Do not retain the old PID as the Agent
identity.

## Example

The runnable
[Whole Definition Upgrade](../../examples/08_runtime/08_12_definition_changes/README.md)
lesson shows the Codec document, Catalog, state migration, stable Ref, and new
PID in one ExUnit test.
