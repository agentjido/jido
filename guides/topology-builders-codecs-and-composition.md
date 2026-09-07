# Topology Builders, Codecs, and Composition

The Topology DSL, Builder, and Codec use one canonical constructor. Choose the
authoring form that makes the system definition clear.

## Use The Builder

```elixir
builder =
  Jido.Topology.Builder.new(name: "built_system")
  |> Jido.Topology.Builder.agent(:leader, MyApp.Cell,
    initial_state: %{label: "leader"}
  )
  |> Jido.Topology.Builder.group(:workers, MyApp.Cell, count: 3)
  |> Jido.Topology.Builder.owns(:leader, :workers)

{:ok, definition} = Jido.Topology.Builder.build(builder)
{:ok, instance} = Jido.Topology.Builder.build(builder, id: "built-1", input: %{})
```

The Builder keeps its first error. Check the final result.

## Encode Static Composition

```elixir
{:ok, document, registry} = Jido.Topology.Codec.encode(definition)
json = JSON.encode!(document)
{:ok, decoded} = Jido.Topology.Codec.decode(JSON.decode!(json), registry)
```

The document contains static topology data. It does not contain instance input,
an expanded plan, PIDs, Agent state, runtime status, or completed work.

Use stable IDs in a trusted `Jido.Agent.Codec.Registry` for stored documents.
Document strings cannot create atoms or derive module names.

## Include Reusable Topologies

An included topology has a stable component key. `inputs` maps parent input into
the child schema. `bind` connects required child Bus imports. Exports expose
selected child Agents, groups, or Buses to the parent.

Use `ref(component, export)` to target an exported child component from the
parent. Jido flattens composition, checks import bindings, prevents export
cycles, and gives every component a stable scoped address.

An encoded included definition is a snapshot of that definition. Decoding does
not load a new definition from the source module.

## Keep Composition Bounded

Jido limits component scopes and validates the expanded member count before
activation. Use input schemas and `max_agents` to reject an unexpectedly large
system.

See [Topology Definitions](topology-definitions.md) and
[Activate And Repair A Topology](activate-and-repair-a-topology.livemd).
