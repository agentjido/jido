# CloudEvents Context

Look up what each Signal attribute means, what values it accepts, and how to carry flat metadata and trace context. Every `Jido.Signal` uses the CloudEvents 1.0 context attributes.

## Envelope attributes

| Attribute | Required | Accepted value | Set by Jido |
| --- | --- | --- | --- |
| `specversion` | Yes | `"1.0"` | Defaults to `"1.0"` in `Jido.Signal.new/1`. |
| `id` | Yes | Non-empty UTF-8 text with no control characters or noncharacters. | Generates a UUID7 when omitted. |
| `source` | Yes | Non-empty URI-reference. | No. |
| `type` | Yes | Non-empty UTF-8 text with no control characters or noncharacters. | No. |
| `subject` | No | Non-empty UTF-8 text, or `nil`. | No. |
| `time` | No | RFC 3339 string, `DateTime`, or `nil`. | No. A `DateTime` becomes an ISO 8601 string. |
| `datacontenttype` | No | Media type, or `nil`. | No. |
| `dataschema` | No | Absolute URI, or `nil`. | No. |
| `data` | No | Any term. | No. |

An input of `"1.0.2"` for `specversion` is accepted and normalized to `"1.0"`. Other versions are rejected.

```elixir
alias Jido.Signal

{:ok, signal} =
  Signal.new("ticket.opened", %{"ticket_id" => "t-81"},
    source: "/support/tickets",
    subject: "t-81",
    time: ~U[2026-03-02 09:15:00Z],
    datacontenttype: "application/json",
    dataschema: "https://example.com/schemas/ticket-opened/v1"
  )

"t-81" = signal.subject
"2026-03-02T09:15:00Z" = signal.time

{:error, "parse error: must be an RFC 3339 timestamp, at time"} =
  Signal.new("ticket.opened", %{}, source: "/support/tickets", time: "yesterday")

{:error, "parse error: must be an absolute URI, at dataschema"} =
  Signal.new("ticket.opened", %{}, source: "/support/tickets", dataschema: "/relative")

{:error, "parse error: must be a valid media type, at datacontenttype"} =
  Signal.new("ticket.opened", %{}, source: "/support/tickets", datacontenttype: "json")
```

Use each field for its CloudEvents purpose:

- `type` names what happened. Routers and the Bus select on it.
- `source` names the producer. `source` plus `id` should identify one event.
- `subject` names the thing the event is about, such as one ticket. Bus selectors can match it.
- `dataschema` names the data version. `Jido.Signal.Catalog` selects a definition with it.

## Absent data and null data

The struct records whether data was supplied. `data_present?` separates an absent `data` member from an explicit `null`, and `data_base64?` records raw bytes. Treat these two fields as internal bookkeeping for the codec.

```elixir
alias Jido.Signal

no_data = Signal.new!(type: "ticket.closed", source: "/support/tickets")
null_data = Signal.new!(type: "ticket.closed", source: "/support/tickets", data: nil)

false = no_data.data_present?
true = null_data.data_present?
nil = no_data.data
nil = null_data.data
```

[Signal Wire Format](signal-codecs.md) shows how each case encodes.

## Extension attributes

An extension attribute is flat metadata that travels with the envelope. Use it for transport concerns, such as a tenant ID or a partition key. Put domain fields in `data`, where a schema can validate them.

The `extensions` field holds them under string names. These rules apply to all extensions:

- A name starts with a lower-case letter, contains only lower-case letters and digits, and has at most 20 characters.
- A name cannot be a core attribute name such as `source`.
- A value is a boolean, a signed 32-bit integer, or a binary.

The constructors treat any unknown attribute as an extension, so you can pass one directly or through `:extensions`.

```elixir
alias Jido.Signal

{:ok, signal} =
  Signal.new("ticket.opened", %{},
    source: "/support/tickets",
    tenantid: "acme",
    extensions: %{"region" => "eu"}
  )

%{"tenantid" => "acme", "region" => "eu"} = signal.extensions

{:error, "parse error: extension name \"tenantId\"" <> _rest} =
  Signal.new("ticket.opened", %{}, source: "/support/tickets", tenantId: "acme")
```

A misspelled core attribute also becomes an extension. For example, `sorce: "/x"` is a valid extension name, and the Signal then fails because `source` is missing.

Use these functions on an existing Signal. `Jido.Signal.Context` has the same operations as `put/3`, `get/2`, `delete/2`, and `names/1`, and adds `normalize/1` to validate a whole map.

```elixir
alias Jido.Signal

signal = Signal.new!("ticket.opened", %{}, source: "/support/tickets")

{:ok, signal} = Signal.put_context(signal, :tenantid, "acme")
{:ok, signal} = Signal.put_context(signal, "attempt", 2)

"acme" = Signal.get_context(signal, :tenantid)
nil = Signal.get_context(signal, "missing")
["attempt", "tenantid"] = signal |> Signal.list_context() |> Enum.sort()

signal = Signal.delete_context(signal, "attempt")
["tenantid"] = Signal.list_context(signal)

{:error, "extension name \"source\" conflicts with a CloudEvents attribute"} =
  Signal.put_context(signal, "source", "/other")

{:error, "extension values must be" <> _rest} =
  Signal.put_context(signal, "labels", %{priority: "high"})
```

Extensions are unauthenticated claims from the sender. See [Signal Boundaries](signal-boundaries.md) before you make a decision based on one.

## Trace context

`Jido.Signal.Context` stores a `Jido.Trace` as W3C extension attributes, so the trace crosses every transport that keeps the envelope. `Jido.Signal.Context.trace_names/0` lists the names it uses.

```elixir
alias Jido.Signal
alias Jido.Signal.Context
alias Jido.Trace

["traceparent", "tracestate", "jidocausationid"] = Context.trace_names()

signal = Signal.new!("ticket.opened", %{}, source: "/support/tickets")
nil = Context.get_trace(signal)

{:ok, traced, trace} = Context.ensure_trace(signal)
"00-" <> _rest = Signal.get_context(traced, "traceparent")
^trace = Context.get_trace(traced)

{:ok, ^traced, ^trace} = Context.ensure_trace(traced)

child = Trace.child(trace)
{:ok, follow_up} = Context.put_trace(signal, child)
true = Context.get_trace(follow_up).trace_id == trace.trace_id

untraced = Context.delete_trace(follow_up)
nil = Context.get_trace(untraced)
```

- `Jido.Signal.Context.ensure_trace/2` keeps a valid existing trace, or creates a root trace and stores it.
- `Jido.Signal.Context.put_trace/2` replaces all trace attributes. It returns `{:error, :invalid_trace_context}` for an invalid `Jido.Trace`.
- `Jido.Signal.Context.get_trace/1` returns `nil` when the `traceparent` is missing or invalid.
- `Jido.Signal.Context.delete_trace/1` removes the W3C, causation, and older Jido trace attributes.

[Trace Context](../data/trace-context.md) covers `Jido.Trace` itself.

## On the wire

Extensions sit beside the core attributes in the CloudEvents map. There is no nested `extensions` member on the wire.

```elixir
alias Jido.Signal

signal =
  Signal.new!("ticket.opened", %{"ticket_id" => "t-81"},
    id: "evt-1",
    source: "/support/tickets",
    tenantid: "acme"
  )

%{
  "specversion" => "1.0",
  "id" => "evt-1",
  "type" => "ticket.opened",
  "source" => "/support/tickets",
  "data" => %{"ticket_id" => "t-81"},
  "tenantid" => "acme"
} = Jido.Signal.Codec.to_map(signal)
```

## Related

- [Custom Signals](signals-and-custom-types.md) to fix the envelope in a module.
- [Signal Wire Format](signal-codecs.md) to encode and decode Signals.
