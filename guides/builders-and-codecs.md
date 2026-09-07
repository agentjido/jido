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

Builder options and DSL options reject duplicate keyword keys. Direct Agent
constructors, instance overrides, `Agent.set/2`, and caller context keep the last
value for a repeated key. Supply each key once when moving between authoring
forms. Caller context also accepts `nil` as an empty map.

## Module Roles

An Agent behavior module implements `handle_signal/2`. A module created with
`use Jido.Agent` also supplies static configuration through `__agent_config__/0`.
`Agent.new(module, options)` and `Builder.new(module)` require this authoring
configuration.

Agent Server startup and `SpawnAgent` also accept constructor modules with
`new/0` or `new/1`. Such a constructor can return an Agent whose behavior module
is different. It does not need to declare Agent configuration itself.

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
