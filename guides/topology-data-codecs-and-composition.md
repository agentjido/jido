# Topology Data, Codecs, and Composition

The Topology DSL, data constructors, and Codec share validation. Choose the
form that makes the system definition clear.

## Declare Data

```elixir
{:ok, definition} =
  Jido.Topology.new(
    name: "built_system",
    agents: [%{key: :leader, module: MyApp.Cell, initial_state: %{label: "leader"}, node: node()}],
    groups: [%{key: :workers, module: MyApp.Cell, count: 3}],
    relationships: [%{parent: :leader, child: :workers}]
  )

{:ok, instance} = Jido.Topology.instantiate(definition, id: "built-1", input: %{})
```

Build each collection in its required order. Check the constructor result
before you plan an instance. Use `module.topology()` to read a module definition.

The `node:` option is an exact Erlang node. It can also be a topology input or
member reference. The default is the Controller node.

## Encode Static Composition

```elixir
{:ok, document, registry} = Jido.Topology.Codec.encode(definition)
json = JSON.encode!(document)
{:ok, decoded} = Jido.Topology.Codec.decode(JSON.decode!(json), registry)
```

The document contains static topology data. It does not contain instance input,
an expanded plan, PIDs, Agent state, runtime status, or completed work.

The current V3 Topology document version is 2. The Codec does not decode
version-1 Topology documents.

Use stable IDs in a trusted `Jido.Codec.Registry` for stored documents.
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
