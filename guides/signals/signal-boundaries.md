# Signal Boundaries

Understand which checks run when a Signal enters or leaves your application, and what remains your responsibility. A Signal looks the same in every process, but its contents are only as trustworthy as the checks it has passed.

## What each layer checks

| Layer | Checks | Does not check |
| --- | --- | --- |
| `Jido.Signal.new/3` | Envelope and extension rules. | `data`. |
| `new/2` on a Signal module | Envelope, extensions, and `data` against the schema. | Who built the Signal. |
| `Jido.Signal.Codec` | Size, encoding, envelope, and extensions. | `data` against any schema. |
| `Jido.Signal.Catalog` | Envelope, extensions, an exact definition match, and its `data` schema. `decode/3` also applies the codec checks. | Authority of the sender. |
| `Jido.Signal.Router` | Type path and your predicates. | `data` against any schema. |
| `Jido.Signal.Bus.publish/2` | Envelope and extensions. | `data` against any schema. |

## Accept outside input

For input from a webhook, a queue, or a partner, use `Jido.Signal.Catalog.decode/3`. It checks in this order:

1. The payload is within the size limit.
2. The binary decodes in the selected format, as one Signal. A batch is rejected.
3. The envelope and extensions are valid.
4. The `{type, dataschema}` pair matches a registered definition.
5. The definition's schema accepts `data`.

Build the catalog at startup from an explicit list. Input never selects a module, and the decoder creates no atoms from JSON keys, so write string-key schemas.

```elixir
defmodule GuideBoundaries.PaymentSettled do
  alias Jido.Joi

  use Jido.Signal,
    type: "payment.settled",
    default_source: "/payments",
    schema:
      Joi.object(%{"payment_id" => Joi.string(), "amount_cents" => Joi.integer()},
        unrecognized_keys: :error
      )
end

alias Jido.Signal.Catalog

catalog = Catalog.new!([GuideBoundaries.PaymentSettled])

body = ~s({
  "specversion": "1.0",
  "id": "evt-41",
  "source": "https://partner.example.com/payments",
  "type": "payment.settled",
  "data": {"payment_id": "p-1", "amount_cents": 1250}
})

{:ok, signal} = Catalog.decode(catalog, body)
"evt-41" = signal.id
"https://partner.example.com/payments" = signal.source
%{"payment_id" => "p-1", "amount_cents" => 1250} = signal.data
```

The result keeps the sender's `id`, `source`, `time`, `subject`, and valid extensions. No constructor runs, so no ID is generated.

Each failed step has its own code in `details.code`:

```elixir
alias Jido.Signal.Catalog

catalog = Catalog.new!([GuideBoundaries.PaymentSettled])

code = fn result ->
  {:error, %Jido.Error.ValidationError{details: %{code: code}}} = result
  code
end

:decode_failed = code.(Catalog.decode(catalog, "not json"))
:decode_failed = code.(Catalog.decode(catalog, "[]"))

envelope = %{"specversion" => "1.0", "id" => "evt-1", "source" => "/payments"}

:unknown_type = code.(Catalog.decode(catalog, Map.put(envelope, "type", "payment.voided")))

:invalid_data =
  code.(Catalog.decode(catalog, Map.merge(envelope, %{"type" => "payment.settled", "data" => %{"extra" => true}})))

:decode_failed = code.(Catalog.decode(catalog, ~s({"type":"payment.settled"}), max_payload_bytes: 5))
:invalid_options = code.(Catalog.decode(catalog, envelope, max_payload_bytes: 5))
```

Map input to `decode/3` must be a complete wire envelope and takes no options. Use `Jido.Signal.Catalog.validate/2` for a Signal struct that already exists. [Signal Data Schemas](signal-data-schemas.md) lists all error codes.

## Choose a wire format by trust

JSON is the format for anything that crosses a trust boundary. `format: :erlang_term` is for trusted Erlang and Elixir systems. It decodes in safe mode and refuses compressed terms, but it still accepts any term built from existing atoms. [Signal Wire Format](signal-codecs.md) covers both, including the size limit.

## What a valid Signal does not prove

A Signal carries no signature. A passing check means the Signal has the right shape. It does not establish these facts:

- `source` and `subject` are claims by the sender.
- Extension attributes, including `tenantid`-style names you define, are claims by the sender.
- `traceparent` is a correlation value, and `Jido.Signal.Context.get_trace/1` only checks its format.
- `type` says what the sender reports, and does not grant permission for anything.

The catalog does not authorize operations or execute commands. Decide what a caller may do with your own policy, using an identity you verified at the edge, such as an authenticated connection or a verified signature. Do not set a `tenantid` from the request body and then treat it as verified.

For a live Agent, [Admission and Deadlines](../agent-servers/agent-server-admission.md) and [Plugin Routing](../plugins/plugin-input-and-routes.md) cover where a check can run before a Turn. The Secure Signal example chapter shows a Plugin that verifies signed input. [Security Model](../operations/security.md) describes the wider model.

## Schema code is trusted

Registered Signal modules and their refine and transform functions are application code. They run on untrusted data, so they must handle any input. `Jido.Signal.Catalog` catches a raise, throw, or exit from a callback and returns `:validation_failed`, but it cannot limit what the callback does before it fails.

## Process and node boundaries

| Path | Reach | What the receiver gets |
| --- | --- | --- |
| `:pid`, `:named` dispatch | This node only. A remote PID fails validation. | A BEAM message with the Signal. |
| `Jido.Signal.Bus` | This node only. A remote target returns `{:error, :invalid_target}`. | `{:signal, signal}`, or `{:signal, id, record}` when durable. |
| `:pubsub` dispatch | Every node in the PubSub cluster. | The bare Signal. |
| `:http` dispatch | Any URL you configure. | CloudEvents JSON. |

The HTTP adapter trusts its URL. It allows private network addresses and does not protect against DNS rebinding, so never build the URL from Signal contents or other input. [Signal Dispatch Adapters](dispatch-adapters.md) lists its limits.

## What reaches logs and telemetry

Signal `data` can hold secrets, so the paths that observe a Signal limit what they emit.

The `:logger` dispatch adapter sanitizes `data`. It replaces the values of known sensitive keys, cuts long strings to 160 bytes, keeps 10 items per collection, keeps 3 levels of nesting, and limits the text preview to 240 bytes.

```elixir
alias Jido.Signal
alias Jido.Signal.Dispatch

signal =
  Signal.new!("payment.settled",
    %{"payment_id" => "p-1", "api_key" => "sk-live-123", "card_number" => "4242"},
    source: "/payments"
  )

:ok = Dispatch.dispatch(signal, {:logger, level: :info})
# Logs: SIGNAL: payment.settled from /payments with data=%{"api_key" => "[REDACTED]", "card_number" => "4242", "payment_id" => "p-1"}

:ok = Dispatch.dispatch(signal, {:logger, level: :info, include_data: false})
# Logs: SIGNAL: payment.settled from /payments
```

Redaction matches exact key names, so `card_number` above stays visible. The comparison ignores letter case, treats `-` as `_`, and ignores a leading `x_`. The names are `access_token`, `api_key`, `authorization`, `client_secret`, `cookie`, `credential`, `passphrase`, `password`, `private_key`, `proxy_authorization`, `refresh_token`, `secret`, `set_cookie`, `signature`, `token`, `webhook_secret`, `webhook_signature`, `x_api_key`, and `x_webhook_signature`. Treat this as a backstop. Set `include_data: false` for a Signal that carries sensitive data, and keep secrets out of `data` where you can.

Other paths behave this way:

- Dispatch telemetry reduces an HTTP target to its scheme, host, and port, so paths and query strings stay out of metadata.
- Bus delivery telemetry carries the Signal `id` and `type` and leaves out `data`.
- The Bus removes retained records and subscriptions from its OTP status output.
- `Jido.Error.to_map/1` returns bounded, sanitized details with no stacktrace by default. Use it to report an error outside your system. It has its own redaction rules, based on key name fragments such as `token` and `secret`.

```elixir
error = Jido.Error.validation_error("Rejected", %{field: "payment", api_token: "sk-live-123"})

%{details: %{field: "payment", api_token: "[REDACTED]"}} = Jido.Error.to_map(error)
```

A Signal has no special `Inspect` protection, so `inspect(signal)` prints all of `data`. Some codec and extension errors also quote the rejected input, such as `{:invalid_wire_data, "expected a map, got: 1"}`. Do not log or return these reasons unfiltered when the input can hold secrets.

## Related

- [Signal Data Schemas](signal-data-schemas.md) for definitions and catalog errors.
- [Signal Wire Format](signal-codecs.md) for size limits and formats.
- [Security Model](../operations/security.md) for the wider Jido model.
