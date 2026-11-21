# Jido.Joi Validation

This guide shows which `Jido.Joi` function to call for external input, for new stored state, and for values you already store. It also shows how to control undeclared fields and read validation failures.

`Jido.Joi` is a curated facade over the [Zoi](https://hexdocs.pm/zoi) schema library. A Joi schema is a Zoi schema. Actions, Signals, Agents, and codecs all use Joi for their contracts.

## Choose the operation

The same schema can serve three steps in a value's life. Each step has a different policy.

| Function | Use it for | Can it convert values? | Defaults | Success |
| --- | --- | --- | --- | --- |
| `Jido.Joi.parse/3` | External input | Yes | Added, not validated | `{:ok, value}` |
| `Jido.Joi.initialize/2` | New stored state | No | Added and validated | `{:ok, value}` |
| `Jido.Joi.validate/2` | A value you already store | No | Not added | `:ok` |

```elixir
alias Jido.Joi

schema =
  Joi.object(%{
    invoice_number: Joi.string() |> Joi.min(1),
    attempts: Joi.integer() |> Joi.default(0)
  })

{:ok, %{invoice_number: "INV-7", attempts: 0}} = Joi.parse(schema, %{invoice_number: "INV-7"})
{:ok, %{invoice_number: "INV-7", attempts: 0}} = Joi.initialize(schema, %{invoice_number: "INV-7"})

:ok = Joi.validate(schema, %{invoice_number: "INV-7", attempts: 3})

{:error, [%{code: :required, path: [:attempts]}]} =
  Joi.validate(schema, %{invoice_number: "INV-7"})
```

The last call fails because `Jido.Joi.validate/2` checks the value as it stands. A field with a default is still part of a complete stored value.

### Conversion stops at the input boundary

`Jido.Joi.parse/3` runs coercion and transforms. Use it when the value comes from outside your system.

```elixir
alias Jido.Joi

{:ok, 42} = Joi.parse(Joi.integer(coerce: true), "42")
{:ok, "INV-7"} = Joi.parse(Joi.string() |> Joi.transform(&String.trim/1), "  INV-7 ")
```

`Jido.Joi.initialize/2` and `Jido.Joi.validate/2` reject those schemas before they read the value. The error code is `:joi_invalid_stored_schema`.

```elixir
alias Jido.Joi

{:error, [error]} = Joi.validate(Joi.integer(coerce: true), 42)
:joi_invalid_stored_schema = Joi.error_code(error)
"stored schemas cannot coerce values" = Joi.error_message(error)
```

### Defaults are checked only at initialization

`Jido.Joi.parse/3` inserts a default without validating it. `Jido.Joi.initialize/2` validates the default against its field.

```elixir
alias Jido.Joi

wrong_default = Joi.object(%{currency: Joi.string() |> Joi.default(:usd)})

{:ok, %{currency: :usd}} = Joi.parse(wrong_default, %{})
{:error, [%{code: :invalid_type, path: [:currency]}]} = Joi.initialize(wrong_default, %{})
```

## Write a stored schema

`Jido.Joi.validate_stored_schema/1` reports whether a schema is safe for stored values. `Jido.Joi.initialize/2` and `Jido.Joi.validate/2` run the same check. A stored schema cannot contain:

- coercion, such as `Jido.Joi.integer(coerce: true)`
- `Jido.Joi.transform/2` effects
- `Jido.Joi.codec/3`, `Jido.Joi.lazy/1`, or `Jido.Joi.string_boolean/0`
- the `unrecognized_keys: :strip` policy
- array prefix items or map pattern properties
- anonymous functions, including an anonymous `Jido.Joi.refine/2` function

To add a custom rule to a stored schema, pass `Jido.Joi.refine/2` a `{module, function, args}` tuple. The function receives the value and an options list, then returns `:ok` or `{:error, message}`.

```elixir
defmodule JoiGuide.InvoiceRules do
  def positive(cents, _opts) when cents > 0, do: :ok
  def positive(_cents, _opts), do: {:error, "must be positive"}
end

alias Jido.Joi

total = Joi.integer() |> Joi.refine({JoiGuide.InvoiceRules, :positive, []})

:ok = Joi.validate_stored_schema(total)
:ok = Joi.validate(total, 500)
{:error, [%{code: :custom, message: "must be positive"}]} = Joi.validate(total, -5)

{:error, "anonymous functions are not supported" <> _path} =
  Joi.validate_stored_schema(Joi.integer() |> Joi.refine(fn _cents -> :ok end))
```

If a custom rule returns a changed value, `Jido.Joi.validate/2` fails with the code `:joi_changed_value`. `Jido.Joi.changed_value?/1` tests one error for that code.

## Control undeclared fields

`Jido.Joi.object/2`, `Jido.Joi.map/2`, and `Jido.Joi.keyword/2` are open by default. An open schema validates its declared fields and keeps other fields without reading them. `Jido.Joi.struct/3` is closed by default.

Pass `unrecognized_keys: :error` to close a map or keyword schema.

```elixir
alias Jido.Joi

fields = %{invoice_number: Joi.string()}
input = %{invoice_number: "INV-7", source: "import"}

{:ok, ^input} = Joi.parse(Joi.object(fields), input)

{:error, [%{code: :unrecognized_key, message: "unrecognized key: source"}]} =
  Joi.parse(Joi.object(fields, unrecognized_keys: :error), input)
```

Jido does not use Zoi's `:strip` policy, because stripping changes the shape of the data. Agent state uses a closed boundary at every level. See [Agent State and Schemas](../agents/agent-state-and-schemas.md).

## Define a struct from a schema

Keep one schema as the source of the struct definition. `Jido.Joi.enforce_keys/1` returns the required fields, and `Jido.Joi.struct_fields/1` returns the fields with their defaults.

```elixir
defmodule JoiGuide.Invoice do
  alias Jido.Joi

  @schema Joi.struct(__MODULE__, %{
            number: Joi.string(),
            memo: Joi.string() |> Joi.nullable() |> Joi.optional(),
            status: Joi.enum([:open, :paid]) |> Joi.default(:open)
          })

  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  def schema, do: @schema
end
```

A struct schema accepts a struct, not a plain map, unless you set `coerce: true`. An optional field needs `Jido.Joi.nullable/1` too, because an unset struct field holds `nil`.

```elixir
alias Jido.Joi

:ok = Joi.validate(JoiGuide.Invoice.schema(), %JoiGuide.Invoice{number: "INV-7"})

{:error, [%{code: :invalid_type}]} = Joi.parse(JoiGuide.Invoice.schema(), %{number: "INV-7"})
```

To turn JSON into a struct, use a [codec](versioned-documents.md).

## Read validation errors

Each failure is a list of error values. Read them with the helper functions, and match on the code and path. Keep messages for people.

```elixir
alias Jido.Joi

lines = Joi.list(Joi.object(%{sku: Joi.string()}))

{:error, [error]} = Joi.parse(lines, [%{sku: "A-1"}, %{sku: 7}])

:invalid_type = Joi.error_code(error)
[1, :sku] = Joi.error_path(error)
"invalid type: expected string" = Joi.error_message(error)
"invalid type: expected string, at [1].sku" = Joi.prettify_errors([error])
```

`Jido.Joi.parse!/3` raises `Jido.Joi.ParseError` instead of returning an error tuple. Action validation wraps these errors in the shared taxonomy described in [Jido Error Contracts](error-contracts.md).

## Check authoring data

`Jido.Joi.validate_static/1` checks that a term holds no anonymous functions, PIDs, ports, references, lazy schemas, or improper lists. Jido uses it for data that compile-time definitions embed and that Catalog entries hold. The error names the first bad path.

```elixir
alias Jido.Joi

:ok = Joi.validate_static(%{steps: [:load, :charge], limit: 10})

{:error, "runtime process values are not supported at [:steps, 1]"} =
  Joi.validate_static(%{steps: [:load, self()]})
```

## Project a schema to JSON Schema

`Jido.Joi.to_json_schema/1` returns a map with atom keys. An open schema reports `additionalProperties: true`.

```elixir
alias Jido.Joi

%{
  type: :object,
  additionalProperties: true,
  required: [:invoice_number],
  properties: %{invoice_number: %{type: :string}}
} = Joi.to_json_schema(Joi.object(%{invoice_number: Joi.string()}))
```

## What the facade covers

`Jido.Joi` delegates a fixed part of the Zoi API: scalars, `Jido.Joi.enum/1`, `Jido.Joi.list/1`, `Jido.Joi.tuple/1`, `Jido.Joi.union/1`, `Jido.Joi.discriminated_union/2`, `Jido.Joi.intersection/1`, and the wrappers `Jido.Joi.optional/1`, `Jido.Joi.nullable/1`, `Jido.Joi.default/2`, `Jido.Joi.min/2`, and `Jido.Joi.max/2`. Functions outside that set, such as Zoi's `email/0`, are not on the facade.

## Related

- [Schemas and Validation](../actions/schemas-validation.md) applies these schemas to Action input and output.
- [Signal Data Schemas](../signals/signal-data-schemas.md) applies them to Signal data.
- [Jido.Codec Documents](versioned-documents.md) maps a schema to JSON.
