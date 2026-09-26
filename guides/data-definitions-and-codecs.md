# Data Definitions and Codecs

Use `Jido.Agent.new/1` for a map or keyword declaration. Use `Jido.Agent.Codec`
for a versioned JSON-compatible declaration. These forms produce the same
canonical Agent definition as the module DSL. They do not start a process.

## Declare Data

```elixir
{:ok, definition} =
  Jido.Agent.new(
    name: "built_counter",
    schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    routes: [{"counter.add", MyApp.Add, defaults: %{amount: 1}}]
  )

{:ok, instance} = Jido.Agent.instantiate(definition, id: "built-1")
```

Build route and Plugin lists in the required order. The constructor validates
all fields and executable targets. Plugin order controls callbacks and state
ownership. Check the constructor result before you construct an instance.

Direct Agent constructors, instance overrides, `Jido.Agent.set/2`, and caller
context keep the last value for a repeated keyword key. DSL options reject
duplicate keys. Supply each key once when moving between authoring forms.
Caller context also accepts `nil` as an empty map.

## Module Roles

An Agent behavior module can implement `handle_signal/2` for custom selection.
When this callback is absent, Jido uses the Agent routes. A module created with
`use Jido.Agent` also supplies static configuration through `__agent_config__/0`.
`Agent.instantiate(module, options)` requires this authoring configuration.
Use `module.definition()` to read a module definition.

Agent Server startup and `SpawnChild` also accept constructor modules with
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
The current V3 document version is 2. The Codec does not decode version-1
Agent documents.

## Use A Trusted Registry

`Jido.Codec.Registry` maps stable identifiers to Agent modules, Action and Flow
targets, Plugins, schemas, route match functions, atoms, and static structs.
Agent, Plugin, and Topology Codecs use this one shared Registry.

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

See [Topology Data, Codecs, And Composition](topology-data-codecs-and-composition.md)
and [Portable State And Checkpoints](portable-state-and-checkpoints.md).
