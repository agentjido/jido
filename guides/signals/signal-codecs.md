# Signal Wire Format

Encode Signals for transport, decode them back, and handle each failure. `Jido.Signal.Codec` converts between a `Jido.Signal`, the canonical CloudEvents map, and a binary in JSON or Erlang term format.

The codec checks the envelope and the payload size. It does not check `data` against a schema. Use `Jido.Signal.Catalog.decode/3` for that, as shown in [Signal Boundaries](signal-boundaries.md).

## Encode and decode JSON

JSON is the default format. `Jido.Signal.Codec.serialize/2` returns `{:ok, binary}`, and `Jido.Signal.Codec.deserialize/2` restores an equal Signal.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

signal =
  Signal.new!("invoice.paid", %{"invoice_id" => "inv-9", "amount_cents" => 1_250},
    id: "evt-1",
    source: "/billing",
    subject: "inv-9",
    tenantid: "acme"
  )

{:ok, json} = Codec.serialize(signal)

%{
  "specversion" => "1.0",
  "id" => "evt-1",
  "source" => "/billing",
  "type" => "invoice.paid",
  "subject" => "inv-9",
  "tenantid" => "acme",
  "data" => %{"invoice_id" => "inv-9", "amount_cents" => 1_250}
} = JSON.decode!(json)

{:ok, ^signal} = Codec.deserialize(json)
```

This is CloudEvents structured mode. The `Jido.Signal.Dispatch.Http` adapter sends this same body with the content type `application/cloudevents+json`.

## Work with the canonical map

`Jido.Signal.Codec.to_map/1` returns the map with string keys. Attributes with a `nil` value are left out, and extensions sit at the top level.

`Jido.Signal.Codec.from_map/1` parses a complete map. It adds no defaults, so `specversion` and `id` must be present. Use `Jido.Signal.new/1` when you want a generated ID.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

signal = Signal.new!("invoice.paid", %{"invoice_id" => "inv-9"}, id: "evt-1", source: "/billing")

%{"id" => "evt-1", "type" => "invoice.paid"} = wire = Codec.to_map(signal)
false = Map.has_key?(wire, "subject")
{:ok, ^signal} = Codec.from_map(wire)

{:error, "parse error: specversion is required"} =
  Codec.from_map(%{"id" => "evt-1", "source" => "/billing", "type" => "invoice.paid"})

{:error, "parse error: invalid type: expected string, at id"} =
  Codec.from_map(%{"specversion" => "1.0", "source" => "/billing", "type" => "invoice.paid"})

{:error, "parse error: invalid literal: expected 1.0, at specversion"} =
  Codec.from_map(%{"specversion" => "2.0", "id" => "evt-1", "source" => "/billing", "type" => "invoice.paid"})
```

`from_map/1` treats any unknown member as an extension, so it applies the extension naming rules from [CloudEvents Context](cloudevents-envelope-and-context.md). A member with a `nil` value is dropped.

## How `data` encodes

| Signal `data` | Canonical map |
| --- | --- |
| Never supplied | No `data` member. |
| `nil`, supplied explicitly | `"data" => nil` |
| Valid UTF-8 string | `"data" => string` |
| Binary that is not valid UTF-8 | `"data_base64" => base64_text` |
| Any other term | `"data" => term` |

A decoded `data_base64` value returns as raw bytes in `data`. Input with both `data` and `data_base64` is rejected.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

attrs = [id: "evt-2", source: "/scanner", type: "document.scanned"]

%{} = absent = Codec.to_map(Signal.new!(attrs))
false = Map.has_key?(absent, "data")

%{"data" => nil} = Codec.to_map(Signal.new!(attrs ++ [data: nil]))

raw = Signal.new!(attrs ++ [data: <<0, 255>>])
%{"data_base64" => "AP8="} = Codec.to_map(raw)

{:ok, json} = Codec.serialize(raw)
{:ok, %Signal{data: <<0, 255>>}} = Codec.deserialize(json)

{:error, "parse error: data and data_base64 are mutually exclusive"} =
  Codec.from_map(%{"specversion" => "1.0", "id" => "evt-2", "source" => "/scanner",
    "type" => "document.scanned", "data" => "x", "data_base64" => "AP8="})
```

## JSON accepts JSON values only

JSON encoding allows `nil`, booleans, numbers, valid UTF-8 strings, lists, and maps with string keys, at any depth. It does not allow atom keys, atom values other than `true`, `false`, and `nil`, tuples, or structs. It does not convert them for you.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

for data <- [%{invoice_id: "inv-9"}, %{"status" => :paid}, {:paid, "inv-9"}, %{"on" => ~D[2026-03-02]}] do
  signal = Signal.new!("invoice.paid", data, source: "/billing")

  {:error, {:json_encode_failed, "Signal data must contain JSON values or binary data"}} =
    Codec.serialize(signal)
end
```

Convert these values before you build the Signal, or use a string-key schema as shown in [Signal Data Schemas](signal-data-schemas.md).

## Encode a batch

Pass a list to encode a batch. Decoding a JSON array or term list returns a list. One bad item fails the whole call.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

signals = [
  Signal.new!("invoice.paid", %{"invoice_id" => "inv-9"}, id: "evt-1", source: "/billing"),
  Signal.new!("invoice.paid", %{"invoice_id" => "inv-10"}, id: "evt-2", source: "/billing")
]

{:ok, json} = Codec.serialize(signals)
{:ok, ^signals} = Codec.deserialize(json)

{:error, {:invalid_signal, "expected a Signal, got: :not_a_signal"}} =
  Codec.serialize([hd(signals), :not_a_signal])

{:error, {:invalid_wire_data, "expected a map, got: 1"}} = Codec.deserialize("[1]")
```

## Use the Erlang term format

Pass `format: :erlang_term` between trusted Erlang and Elixir systems. It keeps terms that JSON rejects, such as atom keys.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

signal = Signal.new!("invoice.paid", %{invoice_id: "inv-9"}, id: "evt-1", source: "/billing")

{:ok, binary} = Codec.serialize(signal, format: :erlang_term)
{:ok, ^signal} = Codec.deserialize(binary, format: :erlang_term)

{:error, {:unsupported_format, :xml}} = Codec.serialize(signal, format: :xml)
```

Decoding uses `:erlang.binary_to_term/2` with `[:safe]`, rejects compressed terms, and applies the size limit to both the input and the decoded term. It can still build arbitrary terms from existing atoms, so do not use it for untrusted input.

## Limit payload size

Encoded and decoded payloads have a limit of 10,000,000 bytes. Set `:max_payload_bytes` on one call, or set it for the application:

<!-- partial -->
```elixir
config :jido, max_payload_bytes: 1_000_000
```

The per-call option wins over the application value.

```elixir
alias Jido.Signal
alias Jido.Signal.Codec

signal = Signal.new!("invoice.paid", %{"invoice_id" => "inv-9"}, id: "evt-1", source: "/billing")
{:ok, json} = Codec.serialize(signal)
size = byte_size(json)

{:error, {:payload_too_large, ^size, 10}} = Codec.serialize(signal, max_payload_bytes: 10)
{:error, {:payload_too_large, ^size, 10}} = Codec.deserialize(json, max_payload_bytes: 10)
{:error, {:invalid_max_payload_bytes, -1}} = Codec.serialize(signal, max_payload_bytes: -1)
```

## Errors

`serialize/2` and `deserialize/2` return these reasons. `Jido.Signal.Codec.serialize!/2` raises `RuntimeError` for any of them on encode.

| Reason | Cause |
| --- | --- |
| `{:json_encode_failed, message}` | `data` holds a value JSON cannot carry. |
| `{:json_decode_failed, message}` | The binary is not valid JSON. |
| `{:erlang_term_decode_failed, message}` | The binary is compressed, unsafe, or not a valid term. |
| `{:invalid_signal, message}` | A value passed to `serialize/2` is not a Signal. |
| `{:invalid_wire_data, message}` | A decoded item is not a map. |
| `{:unsupported_format, format}` | `:format` is not `:json` or `:erlang_term`. |
| `{:payload_too_large, size, max}` | The payload is over the limit. |
| `{:invalid_max_payload_bytes, max}` | The limit is not a non-negative integer. |
| `{:invalid_options, message}` | The options are not a keyword list. |
| `{:invalid_payload, message}` | The input to `deserialize/2` is not a binary. |
| `{:serialization_failed, message}`, `{:deserialization_failed, message}` | An exception was raised during the call. |
| A string that starts with `"parse error:"` | The decoded envelope is invalid. |

## Older wire input

`from_map/1` accepts `"specversion": "1.0.2"` and normalizes it to `"1.0"`. It also accepts a `jido_schema_version` member with the value `1`, `2`, or `null` and drops it. Other values of that member are rejected.

## Related

- [CloudEvents Context](cloudevents-envelope-and-context.md) for attribute rules.
- [Signal Dispatch Adapters](dispatch-adapters.md) to send encoded Signals over HTTP.
