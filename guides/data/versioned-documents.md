# Jido.Codec Documents

This guide shows how to map a struct to JSON with `use Jido.Codec`, and how to version and route stored documents with `Jido.Codec.Contract`. You choose the storage. Jido does not write these documents anywhere.

The two tools solve different problems, and a module can use either one without the other.

| Tool | Result | Version routing |
| --- | --- | --- |
| `use Jido.Codec` | `from_map/1`, `decode/1`, `dump/1`, and `json_schema/0` on your module | None |
| `Jido.Codec.Contract` | A document that `Jido.Codec.decode_json/2` routes by `"type"` and `"vsn"` | Yes |

Jido ships two versioned document types: `"jido.flow"` version 2 and `"jido.agent.definition"` version 1. Signals have their own format, described in [Signal Wire Format](../signals/signal-codecs.md).

## Map a struct to JSON

Define a Joi schema first, then `use Jido.Codec` with it. Joi stays the only source of types and validation. The `codec/2` macro only changes how a field looks in JSON.

```elixir
defmodule CodecGuide.Address do
  alias Jido.Joi

  @schema Joi.struct(__MODULE__, %{
            street: Joi.string(),
            postal_code: Joi.string()
          })

  use Jido.Codec, schema: @schema
  codec(:postal_code, as: "postalCode")

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  def schema, do: @schema
end

defmodule CodecGuide.Customer do
  alias Jido.Joi

  @schema Joi.struct(__MODULE__, %{
            name: Joi.string(),
            address: CodecGuide.Address.schema(),
            status: Joi.enum([:active, :disabled]),
            note: Joi.string() |> Joi.nullable() |> Joi.default(nil)
          })

  use Jido.Codec, schema: @schema
  codec(:name, decode: :trim, encode: :trim)
  codec(:note, omit: nil)

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  def trim(value), do: String.trim(value)
end
```

Decoding converts JSON names, enum strings, and nested codec structs. Then it validates the result with the schema.

```elixir
json = ~s({"name":" Ada ","address":{"street":"Main","postalCode":"60601"},"status":"active"})

{:ok, customer} = CodecGuide.Customer.decode(json)

"Ada" = customer.name
:active = customer.status
"60601" = customer.address.postal_code
nil = customer.note

%{
  "name" => "Ada",
  "status" => "active",
  "address" => %{"street" => "Main", "postalCode" => "60601"}
} = CodecGuide.Customer.dump(customer)
```

The dumped map omits `"note"` because of `omit: nil`.

### Generated functions

| Function | Input | Failure |
| --- | --- | --- |
| `decode/1` | JSON binary | `{:error, reason}`, with the raw JSON error for malformed input |
| `decode!/1` | JSON binary | Raises |
| `from_map/1` | Decoded JSON map | `{:error, errors}` |
| `from_map!/1` | Decoded JSON map | Raises |
| `dump/1` | Codec value | Returns a JSON-shaped map |
| `json_schema/0` | None | Returns the JSON Schema of the dumped JSON form |

A struct codec also implements `JSON.Encoder`, so `JSON.encode!/1` calls `dump/1`. `json_schema/0` uses the names you set with `:as`, and its `required` list leaves out fields with `omit: nil` or a default. A field without `:as` keeps its atom key.

```elixir
schema = CodecGuide.Customer.json_schema()

%{"postalCode" => %{type: :string}} = schema.properties.address.properties
false = :note in schema.required
```

### Field options

| Option of `codec/2` | Value | Effect |
| --- | --- | --- |
| `:as` | Non-empty string | The JSON field name |
| `:decode` | Function name, `{module, function}`, or `{module, function, args}` | Runs on the JSON value before validation |
| `:encode` | Same forms as `:decode` | Runs on the field value in `dump/1` |
| `:omit` | `nil` | Leaves out the field when its value is `nil` |

The compiler raises `CompileError` for an unknown field, a duplicate JSON name, a lazy schema, or a schema that holds an anonymous function. The schema must describe a struct or a map.

### Validation failures

```elixir
bad_status = ~s({"name":"Ada","address":{"street":"Main","postalCode":"60601"},"status":"closed"})

{:error, [%{code: :invalid_enum_value, path: [:status]}]} = CodecGuide.Customer.decode(bad_status)

{:error, [%{code: :unrecognized_key, path: ["region"]}]} =
  CodecGuide.Customer.from_map(%{"name" => "Ada", "region" => "US"})
```

A struct schema is closed, so an undeclared JSON field is an error. An exception from a `:decode` callback comes back as `{:error, exception}` from `from_map/1`.

## Write a versioned document codec

Implement `Jido.Codec.Contract` when a stored document must outlive its current shape. The module owns one `{type, version}` pair.

| Callback | Returns |
| --- | --- |
| `type/0` | A stable UTF-8 string of 1 to 255 bytes |
| `version/0` | A positive integer |
| `target/0` | The struct this codec writes, or `nil` for a historical reader |
| `encode/2` | `{:ok, document}` or `{:error, exception}`. Optional for a historical reader |
| `decode/2` | `{:ok, struct}` or `{:error, [issue]}` |

Both `encode/2` and `decode/2` receive the Catalog as their second argument, for [portable values and references](portable-values-and-references.md).

```elixir
defmodule CodecGuide.Invoice do
  defstruct [:number, :total_cents]
end

defmodule CodecGuide.InvoiceV2 do
  @behaviour Jido.Codec.Contract

  alias Jido.Codec.Issue
  alias CodecGuide.Invoice

  @impl true
  def type, do: "billing.invoice"
  @impl true
  def version, do: 2
  @impl true
  def target, do: Invoice

  @impl true
  def encode(%Invoice{} = invoice, _catalog) do
    {:ok,
     %{
       "type" => type(),
       "vsn" => version(),
       "number" => invoice.number,
       "total_cents" => invoice.total_cents
     }}
  end

  @impl true
  def decode(%{"number" => number, "total_cents" => cents}, _catalog)
      when is_binary(number) and is_integer(cents) do
    {:ok, struct!(Invoice, number: number, total_cents: cents)}
  end

  def decode(_document, _catalog) do
    {:error, [Issue.new(:invalid_invoice, ["total_cents"], "total_cents must be an integer")]}
  end
end
```

The document must carry the codec's own `"type"` and `"vsn"`. `Jido.Codec.encode/2` checks them, and returns `:unsupported_document` when they differ.

## Encode and decode

Every call needs a Catalog, even if this codec never reads it. Pass `:catalog` and `:codec` to select both explicitly.

```elixir
options = [catalog: Jido.Catalog.new!([]), codec: CodecGuide.InvoiceV2]
invoice = struct!(CodecGuide.Invoice, number: "INV-7", total_cents: 500)

{:ok, document} = Jido.Codec.encode(invoice, options)
%{"type" => "billing.invoice", "vsn" => 2, "number" => "INV-7"} = document

{:ok, json} = Jido.Codec.encode_json(invoice, options)

{:ok, ^invoice} = Jido.Codec.decode_json(json, options)
{:ok, ^invoice} = Jido.Codec.decode(document, options)
```

| Option | Default | Meaning |
| --- | --- | --- |
| `:catalog` | The published Catalog | The `Jido.Catalog` passed to the codec |
| `:codec` | Routed through Discovery | One codec module to use |
| `:maximum_json_bytes` | 8,388,608 | The limit on the encoded document |

An unknown option raises `ArgumentError`. Without an explicit `:catalog`, the call reads the Catalog that Discovery publishes, and raises `Jido.Codec.Error.InternalError` until the first scan finishes. See [Catalog and Discovery](catalog.md).

## Read an older version

A historical reader returns `nil` from `target/0` and implements only `decode/2`. It reads the old document into the current struct. The next write then produces the current version.

```elixir
defmodule CodecGuide.InvoiceV1 do
  @behaviour Jido.Codec.Contract

  @impl true
  def type, do: "billing.invoice"
  @impl true
  def version, do: 1
  @impl true
  def target, do: nil

  @impl true
  def decode(%{"number" => number, "total" => total}, _catalog) do
    {:ok, struct!(CodecGuide.Invoice, number: number, total_cents: round(total * 100))}
  end
end

old = %{"type" => "billing.invoice", "vsn" => 1, "number" => "INV-1", "total" => 1.5}
catalog = Jido.Catalog.new!([])

{:ok, upgraded} = Jido.Codec.decode(old, catalog: catalog, codec: CodecGuide.InvoiceV1)
150 = upgraded.total_cents

{:ok, %{"vsn" => 2}} = Jido.Codec.encode(upgraded, catalog: catalog, codec: CodecGuide.InvoiceV2)
```

Jido does not upgrade stored documents on its own. Rewrite them when your application decides to.

## Route documents through Discovery

Without `:codec`, `Jido.Codec.decode_json/2` finds the codec by `"type"` and `"vsn"` in the index that `Jido.Catalog.Discovery` publishes. In an application, Discovery finds every module that declares the `Jido.Codec.Contract` behaviour. These explicit module sources stand in for an application scan.

```elixir
wait_for_catalog = fn ->
  Enum.find_value(1..200, fn _attempt ->
    Process.sleep(50)
    Jido.Catalog.Discovery.ready?()
  end)
end

true = wait_for_catalog.()

:ok =
  Jido.Catalog.Discovery.refresh(
    applications: [],
    modules: [{CodecGuide.InvoiceV1, :billing}, {CodecGuide.InvoiceV2, :billing}]
  )

{:ok, %CodecGuide.Invoice{total_cents: 150}} = Jido.Codec.decode(old)
{:ok, %{"vsn" => 2}} = Jido.Codec.encode(upgraded)

{:error, [%Jido.Codec.Issue{code: :unsupported_document, details: %{supported_vsns: [1, 2]}}]} =
  Jido.Codec.decode(%{"type" => "billing.invoice", "vsn" => 3})
```

Encoding finds the writer in this order:

1. The `:codec` option.
2. The `Jido.Codec.Encoder` protocol, when the value's struct implements it.
3. The published index, by the `target/0` of each current writer.

Implement `Jido.Codec.Encoder` when you want to select the writer without the published index.

<!-- partial -->
```elixir
defimpl Jido.Codec.Encoder, for: CodecGuide.Invoice do
  def codec(_invoice), do: {:ok, CodecGuide.InvoiceV2}
end
```

Discovery fails the refresh if two modules claim one `{type, version}` pair, or if two current writers claim one target.

## Handle failures

Decoding returns a list of `Jido.Codec.Issue` values. Each has a stable `:code`, a `:path` of JSON keys and indexes, a `:message`, and JSON-safe `:details`. `Jido.Codec.Issue.to_map/1` converts one to data.

```elixir
options = [catalog: Jido.Catalog.new!([]), codec: CodecGuide.InvoiceV2]

{:error, [%{code: :invalid_invoice, path: ["total_cents"]}]} =
  Jido.Codec.decode(%{"type" => "billing.invoice", "vsn" => 2, "number" => "INV-7"}, options)

{:error, [%{code: :duplicate_key, path: ["vsn"]}]} =
  Jido.Codec.decode_json(~s({"type":"billing.invoice","vsn":2,"vsn":2}), options)
```

| Issue code | Meaning |
| --- | --- |
| `:invalid_json` | The JSON is malformed, is not a string, or exceeds the byte limit in `Jido.Codec.decode_json/2` |
| `:duplicate_key` | A JSON object repeats a key |
| `:invalid_document` | The document is not a JSON object |
| `:missing_document_type`, `:invalid_document_type` | `"type"` is absent or is not a string |
| `:missing_document_vsn`, `:invalid_document_vsn` | `"vsn"` is absent or is not a positive integer |
| `:unsupported_document` | No codec handles this type and version. `details.supported_vsns` lists the known versions |
| `:bytes`, `:json` | `Jido.Codec.decode/2` found too many bytes, or a value that does not survive JSON |
| `:depth`, `:collection`, `:nodes`, `:list` | The document breaks a shape limit |
| `:codec_failure` | The codec raised, threw, or exited. Jido contains the failure |
| `:invalid_codec_return` | The codec returned a value outside its contract |
| `:invalid_codec` | The module does not satisfy `Jido.Codec.Contract` |

Encoding returns one exception instead of a list. `Jido.Codec.Error.InvalidError` covers bad values, such as `:unsupported_value` and `:document_too_large`. `Jido.Codec.Error.InternalError` covers codec and Catalog failures, such as `:codec_failure` and `:invalid_codec`. Both have a `:code` field.

```elixir
options = [catalog: Jido.Catalog.new!([]), codec: CodecGuide.InvoiceV2]
invoice = struct!(CodecGuide.Invoice, number: "INV-7", total_cents: 500)

{:error, %Jido.Codec.Error.InvalidError{code: :document_too_large}} =
  Jido.Codec.encode(invoice, Keyword.put(options, :maximum_json_bytes, 8))

{:error, %Jido.Codec.Error.InternalError{code: :invalid_codec}} =
  Jido.Codec.encode(invoice, Keyword.put(options, :codec, CodecGuide.InvoiceV1))
```

## Resource limits

Decoding and encoding both enforce these limits on the complete document.

| Limit | Value |
| --- | --- |
| Encoded JSON bytes | 8,388,608 by default |
| Nesting depth | 100 |
| Items in one list or map | 10,000 |
| Total nodes in a document | 100,000 |

Only the byte limit is configurable. Set it per call with `:maximum_json_bytes`, or for the application:

<!-- partial -->
```elixir
config :jido, Jido.Codec, maximum_json_bytes: 1_048_576
```

`Jido.Codec.Document` exposes these checks through `Jido.Codec.Document.decode_json/2`, `Jido.Codec.Document.check/1`, and `Jido.Codec.Document.check_json/2`.

These limits protect resources. They do not make a document trustworthy. `Jido.Codec` treats documents as trusted runtime data, so check who can write them, as described in the [Security Model](../operations/security.md).

## Related

- [Portable Values](portable-values-and-references.md) covers atoms and references inside a document.
- [Store Flows as JSON](../flow-data/flow-storage.md) applies this workflow to Flows.
- [Checkpoints and Upgrades](../durability/checkpoints-and-data-upgrades.md) covers stored Agent data.
