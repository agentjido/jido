# Agent Authoring Migration

This guide explains the definition and instance boundary in the new Agent
authoring model.

## One canonical Agent value

`%Jido.Agent{}` is the only canonical root. Use the same value for a definition
and an instance. A definition has no `id`, `state`, or `agent_module`. An
instance has runtime values in these fields.

Generated modules expose their definition through `agent/0`.

```elixir
definition = MyApp.CounterAgent.agent()
instance = MyApp.CounterAgent.new(id: "counter-1")
```

## Root constructor change

`Jido.Agent.new/1` and `Jido.Agent.new!/1` are inert definition constructors.
They no longer accept runtime identity or state as constructor data.

Before:

```elixir
{:ok, agent} = Jido.Agent.new(%{id: "counter-1", state: %{count: 1}})
```

After:

```elixir
definition =
  Jido.Agent.new!(
    name: "counter_agent",
    state_schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  )

{:ok, instance} =
  Jido.Agent.instantiate(definition, id: "counter-1", state: %{count: 1})
```

For a generated module, keep the normal call:

```elixir
instance = MyApp.CounterAgent.new(id: "counter-1", state: %{count: 1})
```

Generated `new/1` delegates to `Jido.Agent.instantiate/2`. Generated
`validate/2` remains as a temporary state-validation shim.

## Keyword compatibility

The compatibility lowerer accepts these current names:

| Current input | Canonical field |
|---|---|
| `schema:` | `state_schema` |
| `signal_routes:` | `routes` |
| old plugin module or tuple | `Jido.Agent.Plugin` |
| `default_plugins:` | `Jido.Agent.PluginDefaults` |

Old plugin forms continue to compile:

```elixir
use Jido.Agent,
  name: "support_agent",
  plugins: [
    MyApp.SupportPlugin,
    {MyApp.AuditPlugin, %{level: :full}},
    {MyApp.ChannelPlugin, as: :support, room: "help"}
  ],
  default_plugins: false
```

New code should use the module DSL or canonical data:

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent, name: "support_agent"

  agent do
    state_schema(MyApp.AgentSchemas.support_state())
    plugin_defaults(:none)
    plugin(MyApp.SupportPlugin)
    route("support.requested", MyApp.HandleSupport)
  end
end
```

## Strategy migration

New Agent authoring does not select a strategy.

An explicit old Direct marker gives a warning and has no place in the canonical
Agent value, compiled data, Registry, Codec document, or semantic identity.
Remove it:

```elixir
# Before
use Jido.Agent,
  name: "support_agent",
  strategy: Jido.Agent.Strategy.Direct

# After
use Jido.Agent,
  name: "support_agent"
```

Generated modules keep a temporary Direct runtime binding because current
`cmd/2` and AgentServer paths still call the module execution callbacks. This
binding is outside Agent equality and storage.

A custom `strategy:` declaration now fails with migration help. Move domain
work to Actions and use routes to select the Actions. If an existing runtime
integration still needs an execution callback, keep it as a temporary trusted
module callback. Do not put the callback binding in `%Jido.Agent{}`.

## Metadata migration

`category`, `tags`, and `vsn` are discovery or package metadata. Generated
module accessors can continue to expose them. They are not fields in the
canonical Agent definition and do not affect equality or semantic identity.

`jido` and `agent_module` are runtime or compile bindings. They also do not
affect definition equality, Codec data, or semantic identity.

## Definition storage

Use `Jido.Agent.Codec` with `Jido.Agent.Registry`. The caller owns JSON:

```elixir
{:ok, document} = Jido.Agent.Codec.encode(definition, registry)
json = Jason.encode!(document)

{:ok, decoded} =
  json
  |> Jason.decode!()
  |> Jido.Agent.Codec.decode(registry)
```

The Codec rejects runtime fields and strategy data. See
[Agent Storage](agent-storage.md).

## Migration checklist

1. Replace old direct root instance calls with `Jido.Agent.instantiate/2`.
2. Keep generated `MyAgent.new/1` calls for normal instance creation.
3. Use `MyAgent.agent/0` when you need the definition.
4. Rename `schema` to `state_schema` in new code.
5. Rename `signal_routes` to `routes` or use DSL `route` declarations.
6. Move default plugin policy to `plugin_defaults`.
7. Remove explicit Direct strategy markers.
8. Replace custom strategy declarations with Actions and routes.
9. Keep category, tags, version, and host bindings outside canonical data.
10. Store definitions with Codec, Registry, and caller-owned JSON.
