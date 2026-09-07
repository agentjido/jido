# Authoring Extensions

An Agent authoring extension adds static declarations and lowers them into
ordinary Agent configuration. It extends how an application describes an Agent;
it does not add an imperative runtime path.

## Implement The Contract

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

See [Agent DSL](agent-dsl.livemd), [Builders And Codecs](builders-and-codecs.md),
and [Extension Boundaries](extension-boundaries.md).
