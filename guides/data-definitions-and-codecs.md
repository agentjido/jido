# Data Definitions and Codecs

Use `Jido.Agent.define/1` for a map or keyword declaration. Use `Jido.Agent.Codec`
for a versioned JSON-compatible declaration. These forms produce the same
canonical Agent definition as the module DSL. They do not start a process.

## Declare Data

```elixir
{:ok, definition} =
  Jido.Agent.define(
    name: "built_counter",
    schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    routes: [%{path: "counter.add", handler: %{kind: :action, target: MyApp.Add},
               defaults: %{amount: 1}}]
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

Routes select Actions or Flows. Put state-dependent decisions in that work.
A module created with
`use Jido.Agent` compiles its static fields into a neutral Agent value.
`module.definition()` checks the current Plugin and Action contracts before it
returns that value. `Agent.instantiate(module, options)` uses the same current
contracts to construct an instance. Plugin specifications and complete state
schemas are derived for each use; they are not stored in the compiled value.

Pass a definition, Agent module, or Agent instance to Agent Server startup.
Use `Jido.Agent.instantiate/2` to create an instance from a definition.

## Encode Static Authoring Data

```elixir
{:ok, document, registry} = Jido.Agent.Codec.encode(definition)
json = JSON.encode!(document)

{:ok, decoded} =
  Jido.Agent.Codec.decode(JSON.decode!(json), registry)
```

The document stores an Agent definition or a complete instance with its state.
It does not store runtime resources, completed work, or a live deployment.
The current Agent document version is 1. The Codec rejects other versions.

## Use A Trusted Registry

`Jido.Codec.Registry` maps stable identifiers to Agent modules, Action and Flow
targets, Plugins, schemas, route match functions, atoms, and static structs.
Agent, Plugin, and Topology Codecs use this one shared Registry.

Document strings do not create atoms or derive module names. Treat the Registry
as an application allowlist. For stored documents, define stable application
identifiers instead of using generated temporary identifiers.

## Import An Agent With Plugins

Agent JSON stores Plugin contributions in `extensions`. Each contribution
contains its provider, ID, version, and configuration data. Register the Plugin
module as a trusted `:plugin` reference, and register its option keys and any
other referenced values. Import validates the current Plugin contract and state
schema. Missing references and invalid Plugin options fail before startup.

```elixir
extensions = [
  %{
    id: Jido.Plugin.Scheduler.id(),
    provider: Jido.Plugin.Scheduler,
    vsn: Jido.Plugin.Scheduler.vsn(),
    data: %{retry_delay_ms: 25}
  }
]
```

Import does not activate Plugins. Instantiate the decoded definition, start it
with `Jido.start_agent/2`, and call `Jido.AgentServer.await_ready/1`. AgentServer
then starts each declared runtime Plugin. An imported Action or Flow route can
return Scheduler Directives through the same commit boundary as a DSL Agent.

The separate `Jido.Plugin.Scheduler.DSL` provider validates static `schedules`
data. It does not start the Scheduler runtime or activate those schedules.
Use the runtime `Jido.Plugin.Scheduler` contribution for this use case.

See the [data-defined Agent example](https://github.com/agentjido/jido/tree/release/v3/examples/01_basic/01_07_data_defined_agent)
for a JSON import with stable Registry IDs, Plugin options, and a scheduled
command. A Plugin's code must already be installed and allowed by the host.

## Keep Formats Separate

| Format | Purpose |
| --- | --- |
| Agent Codec | Agent definition or complete instance data |
| Plugin Codec | Plugin module and options |
| Topology Codec | Static system composition |
| Agent checkpoint | Portable identity and live state |

The codecs limit depth, node counts, collection size, and string size. Apply a
smaller limit at an untrusted ingestion boundary when your application needs it.

See [Topology Data, Codecs, And Composition](topology-data-codecs-and-composition.md)
and [Portable State And Checkpoints](portable-state-and-checkpoints.md).
