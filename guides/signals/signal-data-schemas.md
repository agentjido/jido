# Signal Data Schemas

Validate Signal `data` with a static Joi schema, keep data ready for JSON, and select the right schema version for a Signal that you did not build. [Custom Signals](signals-and-custom-types.md) introduces the module form. [Jido.Joi Validation](../data/joi-validation.md) covers the Joi API.

## Where validation runs

A schema runs in three places:

- `new/2` and `new!/2` on the Signal module.
- `validate_data/1` on the Signal module.
- `Jido.Signal.Catalog.validate/2` and `Jido.Signal.Catalog.decode/3`.

`Jido.Signal.new/3`, `Jido.Signal.Codec`, `Jido.Signal.Router`, `Jido.Signal.Dispatch`, and `Jido.Signal.Bus` check the envelope or the type only. They do not look up a schema.

## Write a schema

A schema can use defaults, refinements, and transforms. Refinements and transforms must be named `{module, function, args}` values. Each function receives the value, then an options argument.

```elixir
defmodule GuideDataSchemas.Rules do
  def valid_sku(sku, _opts) do
    if String.starts_with?(sku, "SKU-"), do: :ok, else: {:error, "must start with SKU-"}
  end

  def upcase(value, _opts), do: String.upcase(value)
end

defmodule GuideDataSchemas.StockChanged do
  alias Jido.Joi

  use Jido.Signal,
    type: "inventory.stock.changed",
    default_source: "/warehouses/east",
    schema:
      Joi.object(%{
        "sku" => Joi.string() |> Joi.refine({GuideDataSchemas.Rules, :valid_sku, []}),
        "quantity" => Joi.integer(),
        "unit" => Joi.string() |> Joi.transform({GuideDataSchemas.Rules, :upcase, []}) |> Joi.default("EA")
      })
end

alias GuideDataSchemas.StockChanged

{:ok, signal} = StockChanged.new(%{"sku" => "SKU-42", "quantity" => 7})
%{"sku" => "SKU-42", "quantity" => 7, "unit" => "EA"} = signal.data

{:error, [%{path: ["sku"], message: "must start with SKU-"}]} =
  StockChanged.new(%{"sku" => "42", "quantity" => 7})

{:ok, %{"unit" => "BOX"}} =
  StockChanged.validate_data(%{"sku" => "SKU-42", "quantity" => 7, "unit" => "box"})
```

## Schemas are static

The schema is stored in the compiled module. Compilation fails with `CompileError` when it contains:

- An anonymous function, including one nested in MFA arguments.
- A lazy schema.
- A runtime process value, such as a PID, port, or reference.

Named functions run at validation time and are trusted code.

## Use string keys for JSON data

Choose the key type for how the Signal travels. `Jido.Signal.Codec` encodes JSON only when every map key is a string, and it never converts JSON keys to atoms when it decodes.

| Data travels | Use |
| --- | --- |
| Over JSON, HTTP, or through `Jido.Signal.Catalog.decode/3` | String-key schemas such as `%{"sku" => Joi.string()}`. |
| Only inside one BEAM application | Atom-key or string-key schemas. |

```elixir
alias Jido.Signal.Codec

defmodule GuideDataSchemas.AtomKeyed do
  alias Jido.Joi

  use Jido.Signal,
    type: "inventory.audit.requested",
    default_source: "/warehouses/east",
    schema: Joi.object(%{sku: Joi.string()})
end

atom_keyed = GuideDataSchemas.AtomKeyed.new!(%{sku: "SKU-42"})

{:error, {:json_encode_failed, "Signal data must contain JSON values or binary data"}} =
  Codec.serialize(atom_keyed)

string_keyed = GuideDataSchemas.StockChanged.new!(%{"sku" => "SKU-42", "quantity" => 7})
{:ok, _json} = Codec.serialize(string_keyed)
```

## Accept data that is not a map

A schema can describe any value. A module with no `:schema` accepts any data, and `new/2` still validates the envelope.

```elixir
defmodule GuideDataSchemas.TicketNote do
  use Jido.Signal,
    type: "ticket.note.added",
    default_source: "/support/tickets",
    schema: Jido.Joi.string()
end

defmodule GuideDataSchemas.RawWebhook do
  use Jido.Signal,
    type: "webhook.received",
    default_source: "/webhooks"
end

"Customer replied" = GuideDataSchemas.TicketNote.new!("Customer replied").data
{:error, [_error]} = GuideDataSchemas.TicketNote.new(42)
{:raw, <<0, 1>>} = GuideDataSchemas.RawWebhook.new!({:raw, <<0, 1>>}).data
```

## Version a schema with `dataschema`

Each schema version gets its own module with the same `type` and a different `:dataschema` URI. The definition sets `dataschema` on each Signal it builds, so the Signal names its own version.

`Jido.Signal.Catalog` selects a definition from that pair. A catalog is an immutable value that you build from an explicit list of modules. It never selects a module from input or creates a module name from text.

```elixir
defmodule GuideDataSchemas.MessageV1 do
  alias Jido.Joi

  use Jido.Signal,
    type: "chat.message.received",
    default_source: "/chat",
    dataschema: "https://example.com/schemas/chat-message/v1",
    schema: Joi.object(%{"text" => Joi.string()}, unrecognized_keys: :error)
end

defmodule GuideDataSchemas.MessageV2 do
  alias Jido.Joi

  use Jido.Signal,
    type: "chat.message.received",
    default_source: "/chat",
    dataschema: "https://example.com/schemas/chat-message/v2",
    schema:
      Joi.object(%{"body" => Joi.string(), "lang" => Joi.string() |> Joi.default("en")},
        unrecognized_keys: :error
      )
end

alias GuideDataSchemas.{MessageV1, MessageV2}
alias Jido.Signal
alias Jido.Signal.Catalog

catalog = Catalog.new!([MessageV1, MessageV2])

v1 = MessageV1.new!(%{"text" => "hello"})
{:ok, ^v1} = Catalog.validate(catalog, v1)

incoming =
  Signal.new!("chat.message.received", %{"body" => "hello"},
    id: "evt-7",
    source: "/partners/acme",
    dataschema: "https://example.com/schemas/chat-message/v2"
  )

{:ok, validated} = Catalog.validate(catalog, incoming)
%{"body" => "hello", "lang" => "en"} = validated.data
"evt-7" = validated.id
"/partners/acme" = validated.source
```

Validation keeps the Signal's identity. The catalog generates no ID and changes no envelope field. Only `data` can change, through schema defaults and transforms.

The match is exact text on the `{type, dataschema}` pair:

- A definition with no `dataschema` matches only a Signal with no `dataschema`.
- A trailing slash or different letter case in the URI is a different schema.
- Two definitions with the same pair are an error, even when one module appears twice.

The catalog does not migrate data between versions or fetch schemas from their URIs. The URI is only an identifier.

## Catalog errors

Every catalog failure returns `{:error, %Jido.Error.ValidationError{}}`. Branch on `details.code`.

```elixir
alias GuideDataSchemas.{MessageV1, MessageV2}
alias Jido.Signal
alias Jido.Signal.Catalog

catalog = Catalog.new!([MessageV1, MessageV2])

{:error, %Jido.Error.ValidationError{details: %{code: :unknown_type}}} =
  Catalog.validate(catalog, Signal.new!("chat.deleted", %{}, source: "/chat"))

{:error, %{details: %{code: :unknown_dataschema, dataschema: nil}}} =
  Catalog.validate(catalog, Signal.new!("chat.message.received", %{}, source: "/chat"))

bad_data = %{MessageV1.new!(%{"text" => "hello"}) | data: %{"body" => "hello"}}

{:error, %{details: %{code: :invalid_data, definition: MessageV1}}} =
  Catalog.validate(catalog, bad_data)

{:error, %{details: %{code: :duplicate_definition, definitions: [MessageV1, MessageV1]}}} =
  Catalog.new([MessageV1, MessageV1])
```

| `details.code` | Meaning |
| --- | --- |
| `:invalid_definitions` | The registration input or module metadata is invalid. |
| `:duplicate_definition` | Two registrations share one `{type, dataschema}` pair. `details.definitions` lists both modules. |
| `:invalid_input` | Expected a catalog, a Signal, a map, or a binary. |
| `:invalid_options` | Options were passed with map input to `Jido.Signal.Catalog.decode/3`. |
| `:decode_failed` | The wire format or envelope is invalid, or the input is a batch. |
| `:invalid_envelope` | An existing Signal or its extension attributes are invalid. |
| `:unknown_type` | No definition has this type. |
| `:unknown_dataschema` | The type is known, but the schema identity is not. |
| `:invalid_data` | The selected schema rejected the data. `details.reason` holds the Joi errors. |
| `:validation_failed` | A schema callback raised, threw, or exited. |

## Related

- [Signal Boundaries](signal-boundaries.md) to decode untrusted input with `Jido.Signal.Catalog.decode/3`.
- [Signal Wire Format](signal-codecs.md) for the encoding rules behind these checks.
