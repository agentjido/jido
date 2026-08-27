# Agent Storage

Store Agent definitions through `Jido.Agent.Codec` and
`Jido.Agent.Registry`. The Codec owns the versioned neutral document. The
Registry maps stable stored identifiers to trusted host values.

The caller owns JSON parsing and encoding. The Codec does not depend on a JSON
library.

## Encode

```elixir
definition = MyApp.SupportAgent.agent()

registry =
  Jido.Agent.Registry.new!(%{
    "schemas/support-state" => {:schema, MyApp.AgentSchemas.support_state()},
    "plugins/support" => {:plugin, MyApp.SupportPlugin},
    "actions/handle-support" => {:action, MyApp.HandleSupport}
  })

{:ok, document} = Jido.Agent.Codec.encode(definition, registry)
json_bytes = Jason.encode!(document)

MyApp.DefinitionStore.put("support-agent-v1", json_bytes)
```

For temporary storage, `Jido.Agent.Codec.encode/1` can derive a Registry:

```elixir
{:ok, document, temporary_registry} = Jido.Agent.Codec.encode(definition)
```

Generated Registry identifiers are deterministic for the exact definition.
They are not durable application identifiers. Use a caller-owned Registry for
long-lived documents.

## Decode

```elixir
json_bytes = MyApp.DefinitionStore.fetch!("support-agent-v1")
document = Jason.decode!(json_bytes)

{:ok, definition} = Jido.Agent.Codec.decode(document, registry)
{:ok, instance} = Jido.Agent.instantiate(definition, id: "support-42")
```

`decode/2` returns the first error. `diagnose/2` returns ordered errors with
document paths. Neither function returns a partial Agent.

## Stored data boundary

The Codec accepts definition-only values. It rejects `id`, `state`,
`agent_module`, and strategy data. It also rejects unknown root and nested
fields.

The document can contain identifiers for modules, schemas, external match
functions, registered atoms, and extension values. Stored text cannot create a
module or atom. The Registry must contain each trusted value before decode.

Codec storage is different from runtime checkpoint storage. Use Codec for an
Agent definition. Use the runtime persistence APIs for an Agent instance and
its state.
