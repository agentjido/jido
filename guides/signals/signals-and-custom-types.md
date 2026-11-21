# Custom Signals

Define a Signal module when one event type has a fixed name, source, and data shape. This guide shows when to use a module instead of `Jido.Signal.new/3`, what `use Jido.Signal` generates, and which values callers can still change.

A Signal is the message that starts a Turn. `Jido.Signal` is an immutable struct with CloudEvents 1.0 attributes. See [CloudEvents Context](cloudevents-envelope-and-context.md) for each attribute.

## Create a Signal without a module

`Jido.Signal.new/3` takes a type, a data value, and attributes. `source` has no default, so you must pass it.

```elixir
alias Jido.Signal

{:ok, signal} = Signal.new("order.placed", %{"order_id" => "ord-100"}, source: "/shop/orders")

"order.placed" = signal.type
"/shop/orders" = signal.source
"1.0" = signal.specversion
true = Jido.Id.uuid7?(signal.id)
nil = signal.time

{:error, "parse error: invalid type: expected string, at source"} =
  Signal.new("order.placed", %{"order_id" => "ord-100"})
```

Jido generates a UUID7 `id` when you omit one. It does not fill in `time` or `source`.

`Jido.Signal.new/1` takes all attributes as one map or keyword list. Both `new` functions have a `new!` form. `Jido.Signal.new!/1` raises `RuntimeError` and `Jido.Signal.new!/3` raises `ArgumentError`.

This form checks the envelope only. It accepts any data value, so use it for a one-off event or for a test.

## Define a Signal module

A Signal module fixes the type and validates data each time you build the Signal.

```elixir
defmodule GuideCustomSignals.OrderPlaced do
  alias Jido.Joi

  use Jido.Signal,
    type: "order.placed",
    default_source: "/shop/orders",
    datacontenttype: "application/json",
    schema:
      Joi.object(%{
        order_id: Joi.string(),
        total_cents: Joi.integer() |> Joi.min(0),
        currency: Joi.string() |> Joi.default("USD")
      })
end

alias GuideCustomSignals.OrderPlaced

{:ok, signal} = OrderPlaced.new(%{order_id: "ord-100", total_cents: 4_200})

"order.placed" = signal.type
"/shop/orders" = signal.source
"application/json" = signal.datacontenttype
%{order_id: "ord-100", total_cents: 4_200, currency: "USD"} = signal.data
```

The Joi schema applied the `currency` default before the Signal was built. [Signal Data Schemas](signal-data-schemas.md) covers schema rules.

## Definition options

`use Jido.Signal` validates its options at compile time. An unknown option raises `CompileError`.

| Option | Required | Value |
| --- | --- | --- |
| `:type` | Yes | Non-empty string. |
| `:default_source` | No | URI-reference used when the caller passes no `source`. |
| `:datacontenttype` | No | Media type, such as `"application/json"`. |
| `:dataschema` | No | Absolute URI that names the schema version. |
| `:schema` | No | Static Joi schema. The default accepts any value. |

Use dot-separated type segments made of letters, digits, `_`, and `-`. The `type` field accepts other text, but `Jido.Signal.Router` only accepts route paths in this form. A Signal module whose type contains `*` cannot be used as a route path.

## Generated functions

The module gets these functions:

| Function | Result |
| --- | --- |
| `new(data \\ %{}, opts \\ [])` | `{:ok, signal}`, a list of Joi errors, or an envelope error string. |
| `new!(data \\ %{}, opts \\ [])` | The Signal. Raises `Jido.Joi.ParseError` for bad data and `ArgumentError` for a bad envelope. |
| `validate_data(data)` | The result of `Jido.Joi.parse/2` with the module schema. |
| `type/0`, `default_source/0`, `datacontenttype/0`, `dataschema/0`, `schema/0` | The compiled definition values. |

`Jido.Signal.defined?/1` returns `true` for a module built this way. It does not create atoms.

```elixir
alias GuideCustomSignals.OrderPlaced

"order.placed" = OrderPlaced.type()
"/shop/orders" = OrderPlaced.default_source()
nil = OrderPlaced.dataschema()

true = Jido.Signal.defined?(OrderPlaced)
false = Jido.Signal.defined?(String)
```

## Handle invalid data

`new/2` returns Joi errors directly. Each error has a `path` and a `message`.

```elixir
alias GuideCustomSignals.OrderPlaced

{:error, [error]} = OrderPlaced.new(%{order_id: "ord-100", total_cents: -1})

[:total_cents] = error.path
is_binary(error.message)
```

An envelope failure, such as a source that is not a URI-reference, returns a string instead:

```elixir
alias GuideCustomSignals.OrderPlaced

{:error, "parse error: must be a valid URI-reference, at source"} =
  OrderPlaced.new(%{order_id: "ord-100", total_cents: 4_200}, source: "has a space")
```

## Choose what callers can change

The definition owns `type`, `dataschema`, and `data`. Options cannot change them. Passing them has no effect, and a definition with no `dataschema` keeps it absent.

All other envelope attributes come from the caller. A caller can override `source` and `datacontenttype`, and can set `id`, `subject`, `time`, and extension attributes.

```elixir
alias GuideCustomSignals.OrderPlaced

signal =
  OrderPlaced.new!(%{order_id: "ord-100", total_cents: 4_200},
    type: "order.cancelled",
    dataschema: "https://example.com/schemas/other",
    source: "/imports/legacy",
    subject: "ord-100",
    id: "import-7",
    tenantid: "acme"
  )

"order.placed" = signal.type
nil = signal.dataschema
"/imports/legacy" = signal.source
"ord-100" = signal.subject
"import-7" = signal.id
%{"tenantid" => "acme"} = signal.extensions
```

A definition with no `:default_source` requires `source` on each call.

## Use the module as a route path

`Jido.Signal.Router` and `Jido.Signal.Bus` accept a Signal module anywhere they accept a path. The module becomes its `type/0` value, as an exact path.

```elixir
alias GuideCustomSignals.OrderPlaced
alias Jido.Signal.Router

router = Router.new!({OrderPlaced, :reserve_stock})
signal = OrderPlaced.new!(%{order_id: "ord-100", total_cents: 4_200})

{:ok, [:reserve_stock]} = Router.route(router, signal)
```

A route on a module matches by type alone. It does not check that the Signal was built by that module, so a Signal from `Jido.Signal.new/3` with the same type also matches. Use `Jido.Signal.Catalog` to validate Signals that you did not build yourself.

## Next steps

- [Signal Data Schemas](signal-data-schemas.md) for schema rules, versions, and revalidation.
- [Signal Routing](routing-and-router-dsl.md) for paths, wildcards, and precedence.
- [Routes and Handlers](../agents/build-agent-routes.livemd) to send Signals to an Agent.
