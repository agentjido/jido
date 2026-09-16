# Authoring Extensions

An authoring extension adds static declarations and lowers them into ordinary
Core configuration. It changes how an application describes an Agent or
Topology. It does not add an imperative runtime path.

## Extend Agent Authoring

An Agent authoring extension lowers static declarations into ordinary Agent
configuration.

## Implement The Agent Contract

An extension module implements `Jido.Agent.Extension`:

```elixir
@behaviour Jido.Agent.Extension

@impl Jido.Agent.Extension
def lower_agent(config, foreign_entities) do
  {:ok, updated_config, remaining_entities}
end
```

Pass authoring extension modules to the Agent:

```elixir
use Jido.Agent, extensions: [MyApp.AgentExtension]
```

Core first collects its data schema, Plugins, routes, and metadata. It then
calls extensions in declaration order.

The same lowerer accepts static data. For example, a label entity can add one
metadata field to a direct definition:

```elixir
defmodule MyApp.Label do
  defstruct [:key, :value]
end

defmodule MyApp.Labels do
  @behaviour Jido.Agent.Extension

  @impl true
  def lower_agent(config, entities) do
    {labels, remaining} = Enum.split_with(entities, &match?(%MyApp.Label{}, &1))

    metadata =
      Enum.reduce(labels, Map.get(config, :metadata, %{}), fn label, values ->
        Map.put(values, label.key, label.value)
      end)

    {:ok, Map.put(config, :metadata, metadata), remaining}
  end
end

source = %{name: "labelled_agent", schema: Zoi.object(%{})}
entities = [struct!(MyApp.Label, key: :owner, value: "app")]
{:ok, lowered} = Jido.Agent.Extension.lower([MyApp.Labels], source, entities)
{:ok, definition} = Jido.Agent.new(lowered)
"app" = definition.metadata.owner
```

`Extension.lower/3` returns lowered data, not a validated Agent. The caller
must pass it to `Jido.Agent.new/1`, Builder, or another normal validator.

## Consume Only Owned Entities

An extension must return the entities that belong to later extensions. After
the last extension runs, no foreign entity can remain. Jido rejects duplicate
extensions, invalid callback results, unclaimed entities, and invalid final
Agent configuration.

## Keep Lowering Static

The lowering callback runs while Jido builds the Agent definition. It must not:

- start a process;
- run an Action or Flow;
- contact a service;
- read changing runtime state; or
- hide executable code in opaque data.

Lowering should produce the same semantic Agent data that the Builder or Codec
can represent. New syntax must not create a second runtime contract.

## Preserve Core Boundaries

An authoring extension can add syntax. It cannot bypass state validation,
Plugin ownership, route selection, Agent Server admission, or commit rules.

If an extension needs a live resource, use a Plugin runtime. If it needs a
system of actors, use a Topology or application supervision tree.

## Extend Topology Authoring

A Topology authoring extension uses the same static lowering model. It can add
entities to sections under `topology do`. The extension implements
`Jido.Topology.Extension`:

```elixir
@behaviour Jido.Topology.Extension

@impl Jido.Topology.Extension
def lower_topology(config, foreign_entities) do
  {:ok, updated_config, remaining_entities}
end
```

Pass it to the Topology declaration:

```elixir
use Jido.Topology, extensions: [MyApp.TopologyExtension]
```

Core collects normal Agents, groups, resources, relationships, connections,
composition data, and startup policy from `topology do`. It then collects
foreign entities from extension sections. Each extension consumes its entities
in extension order and returns ordinary Topology configuration.

The callback receives entity structs, not raw Spark section state. Put required
lowering input in an entity. Use distinct structs for entities with different
meanings. Preserve the relative order of entities that belong to later
extensions. Do not depend on order between separate Spark sections.

The final configuration passes the same validation, composition, planning, and
controller paths as Builder and Codec definitions. An extension can describe a
refined topology, but it cannot add a second activation runtime or put dynamic
runtime data in a static definition.

See [Agent DSL](agent-dsl.livemd), [Builders And Codecs](builders-and-codecs.md),
[Topology Definitions](topology-definitions.md), and
[Extension Boundaries](extension-boundaries.md).
