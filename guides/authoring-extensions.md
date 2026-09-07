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

Core first collects its data schema, Plugins, routes, metadata, and state
budget. It then calls extensions in declaration order.

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
one or more Spark sections, or it can add entities to existing Topology
sections. The extension implements `Jido.Topology.Extension`:

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

Core collects normal Agents, groups, Buses, relationships, connections,
composition data, and startup policy first. It then collects foreign entities
from all extension sections. Each extension consumes its entities in extension
order and returns ordinary Topology configuration.

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
