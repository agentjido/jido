# Agents

<!-- covers: jido.agents_and_actions.schema_defined_agents jido.agents_and_actions.pure_cmd_contract -->

An Agent definition is one inert `%Jido.Agent{}` value. It contains author data
such as the name, state schema, plugins, routes, schedules, extensions, and
portable metadata. It does not contain an instance ID or instance state.

An Agent instance uses the same struct. An instance also has `id`, `state`, and
an optional `agent_module` runtime binding.

## Definition and instance boundary

`Jido.Agent.new/1` and `Jido.Agent.new!/1` make definitions. They do not make an
ID, mount plugins, run callbacks, or start a process.

```elixir
definition =
  Jido.Agent.new!(
    name: "counter_agent",
    state_schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    plugin_defaults: :none
  )

nil = definition.id
nil = definition.state

{:ok, instance} =
  Jido.Agent.instantiate(definition, id: "counter-1", state: %{count: 4})
```

A generated Agent module keeps the normal instance constructor:

```elixir
defmodule MyApp.CounterAgent do
  use Jido.Agent,
    name: "counter_agent",
    state_schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
end

definition = MyApp.CounterAgent.agent()
instance = MyApp.CounterAgent.new(id: "counter-1", state: %{count: 4})
{:ok, instance} = MyApp.CounterAgent.validate(instance)
```

Use `agent/0` to get the inert definition. `new/1` delegates to
`Jido.Agent.instantiate/2`. `validate/2` is a temporary state-validation shim.

## Four authoring forms

All four forms make the same `%Jido.Agent{}` definition.

### Native Elixir data

```elixir
definition =
  Jido.Agent.new!(
    name: "support_agent",
    description: "Handles support requests",
    state_schema: MyApp.AgentSchemas.support_state(),
    plugin_defaults: :none,
    plugins: [
      Jido.Agent.Plugin.new!(module: MyApp.SupportPlugin, config: %{queue: "main"})
    ],
    routes: [{"support.requested", MyApp.HandleSupport}],
    metadata: %{owner: "support"}
  )
```

### Builder

```elixir
definition =
  Jido.Agent.Builder.new("support_agent")
  |> Jido.Agent.Builder.description("Handles support requests")
  |> Jido.Agent.Builder.state_schema(MyApp.AgentSchemas.support_state())
  |> Jido.Agent.Builder.plugin_defaults(:none)
  |> Jido.Agent.Builder.plugin(MyApp.SupportPlugin, config: %{queue: "main"})
  |> Jido.Agent.Builder.route("support.requested", MyApp.HandleSupport)
  |> Jido.Agent.Builder.metadata(%{owner: "support"})
  |> Jido.Agent.Builder.build!()
```

### Module DSL

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    name: "support_agent",
    description: "Handles support requests",
    metadata: %{owner: "support"}

  agent do
    state_schema(MyApp.AgentSchemas.support_state())
    plugin_defaults(:none)
    plugin(MyApp.SupportPlugin, config: %{queue: "main"})
    route("support.requested", MyApp.HandleSupport)
  end
end

definition = MyApp.SupportAgent.agent()
```

The keyword names `schema`, `signal_routes`, and `default_plugins` continue to
work during migration. New code must use `state_schema`, `routes` or `route`,
and `plugin_defaults`.

### Stored document

The Codec works with JSON-compatible Elixir terms. The application owns the
JSON library.

```elixir
registry =
  Jido.Agent.Registry.new!(%{
    "schemas/support-state" => {:schema, MyApp.AgentSchemas.support_state()},
    "plugins/support" => {:plugin, MyApp.SupportPlugin},
    "actions/handle-support" => {:action, MyApp.HandleSupport},
    "atoms/owner" => {:atom, :owner}
  })

{:ok, document} = Jido.Agent.Codec.encode(definition, registry)
json = Jason.encode!(document)

{:ok, decoded} =
  json
  |> Jason.decode!()
  |> Jido.Agent.Codec.decode(registry)
```

See [Agent Storage](agent-storage.md) for the full storage boundary.

## Static state schemas

Schemas must contain static data. Use a named MFA callback for a refinement or
transform. Do not put an anonymous function or closure in a schema.

```elixir
defmodule MyApp.AgentSchemas do
  def counter_state do
    Zoi.object(%{
      count:
        Zoi.integer()
        |> Zoi.refine({__MODULE__, :nonnegative, []})
        |> Zoi.default(0)
    })
  end

  def nonnegative(value) when value >= 0, do: :ok
  def nonnegative(_value), do: {:error, "must be nonnegative"}
end
```

Structural validation, executable validation, decode, and compile do not run
Agent work or start processes. Instantiation is the first boundary that makes
runtime state and mounts plugins.

## Commands and directives

The core operation is `cmd/2`:

```elixir
{instance, directives} = MyApp.SupportAgent.cmd(instance, MyApp.HandleSupport)

{instance, directives} =
  MyApp.SupportAgent.cmd(instance, {MyApp.HandleSupport, %{ticket_id: "T-1"}})
```

The returned instance is complete. Directives describe runtime-owned external
effects. They do not change Agent state.

## Runtime and discovery bindings

`agent_module` and `jido` are runtime or compile bindings. They do not change
definition equality, Codec data, or semantic identity.

`category`, `tags`, and `vsn` are discovery or package metadata. Generated
modules can expose these values, but the values are not canonical Agent fields.

An old explicit Direct strategy option gives a migration warning. Remove the
option. A custom strategy declaration gives a compile error with migration
help. New Agent authoring does not select a strategy.

## Further reading

- [Agent Builder](agent-builder.md)
- [Agent Storage](agent-storage.md)
- [Actions](actions.md)
- [Plugins](plugins.md)
- [Scheduling](scheduling.md)
- [Migration](migration.md)
