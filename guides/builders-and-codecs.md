# Builders and Codecs

Use `Jido.Agent.Builder` for an ordered programmatic declaration. Use
`Jido.Agent.Codec` for a versioned JSON-compatible declaration. Both produce
the same canonical Agent definition as the module DSL. They declare data; they
do not run an actor.

## Declare In Ordered Steps

```elixir
builder =
  Jido.Agent.Builder.new(name: "built_counter")
  |> Jido.Agent.Builder.schema(
    Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  )
  |> Jido.Agent.Builder.route(
    "counter.add",
    MyApp.Add,
    defaults: %{amount: 1}
  )

{:ok, definition} = Jido.Agent.Builder.build(builder)
{:ok, instance} = Jido.Agent.Builder.build(builder, id: "built-1")
```

The Builder preserves its first error. Always check `build/1` or `build/2`.

## Encode Static Authoring Data

```elixir
{:ok, document, registry} = Jido.Agent.Codec.encode(definition)
json = JSON.encode!(document)

{:ok, decoded} =
  Jido.Agent.Codec.decode(JSON.decode!(json), registry)
```

The document stores static Agent configuration. It does not store instance
state, runtime resources, completed work, or a live deployment.

## Use A Trusted Registry

The Registry maps stable identifiers to Agent modules, Action and Flow targets,
Plugins, schemas, route match functions, atoms, and static structs.

Document strings do not create atoms or derive module names. Treat the Registry
as an application allowlist. For stored documents, define stable application
identifiers instead of using generated temporary identifiers.

## Keep Formats Separate

| Format | Purpose |
| --- | --- |
| Agent Codec | Static Agent definition |
| Plugin Codec | Plugin module and options |
| Topology Codec | Static system composition |
| Agent checkpoint | Portable identity and live state |

The codecs limit depth, node counts, collection size, and string size. Apply a
smaller limit at an untrusted ingestion boundary when your application needs it.

See [Topology Builders, Codecs, And Composition](topology-builders-codecs-and-composition.md)
and [Portable State And Checkpoints](portable-state-and-checkpoints.md).
