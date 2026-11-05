# Schemas and Validation

This guide shows how to declare the input and output of an Action, what each schema changes, and how to read validation errors. For the wider Joi data lifecycle, see [Jido.Joi Validation](../data/joi-validation.md).

## Validation order

`Jido.Exec.run/4` and `Jido.Exec.call_action/3` check an Action in this order:

1. `on_before_validate_params/1`, when the Action implements it.
2. The `:schema` input schema.
3. `run/2`, with the validated input.
4. The `:output_schema` output schema, on a successful result.

A failure at any step stops the later steps. Input failures never reach `run/2`.

## Declare input fields

`Jido.Joi.object/2` builds a map schema with atom keys. Each field is required unless you make it optional or give it a default.

```elixir
defmodule Orders.CreateOrder do
  alias Jido.Joi

  use Jido.Action,
    name: "create_order",
    schema:
      Joi.object(%{
        customer_id: Joi.string() |> Joi.min(1),
        channel: Joi.enum([:web, :phone]) |> Joi.default(:web),
        coupon: Joi.string() |> Joi.optional(),
        lines:
          Joi.list(
            Joi.object(%{
              sku: Joi.string(),
              quantity: Joi.integer() |> Joi.min(1)
            })
          )
      })

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:ok, %{channel: :web, customer_id: "c-1", lines: [%{sku: "A-1", quantity: 2}]}} =
  Orders.CreateOrder.validate_params(%{
    customer_id: "c-1",
    lines: [%{sku: "A-1", quantity: 2}]
  })
```

The default of `Joi.default/2` appears in the validated map. An omitted optional field stays absent.

Without `:schema`, the Action uses `Jido.Joi.map()`. That schema accepts any map and rejects every other value.

## Match atom keys

Field names in `Jido.Joi.object/2` above are atoms. A map with string keys does not satisfy them, even with the same names.

```elixir
{:error, %Jido.Error.ValidationError{message: message}} =
  Orders.CreateOrder.validate_params(%{"customer_id" => "c-1", "lines" => []})

true = message =~ "is required, at customer_id"
```

Set `coerce: true` on each `Jido.Joi.object/2` level to read string keys as the declared atom keys. Otherwise convert external JSON before it reaches the Action, or prepare it in `on_before_validate_params/1`. Do not create atoms from untrusted input.

## Coerce values

Joi does not convert values by default. Set `coerce: true` on a field to accept a convertible value.

```elixir
defmodule Orders.SetQuantity do
  alias Jido.Joi

  use Jido.Action,
    name: "set_quantity",
    schema: Joi.object(%{quantity: Joi.integer(coerce: true)})

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:ok, %{quantity: 3}} = Orders.SetQuantity.validate_params(%{quantity: "3"})
```

## Choose an unknown-key policy

Schemas from `Jido.Joi.object/2` and `Jido.Joi.map/0` are open. They validate declared fields and pass other fields through without checks. Set `unrecognized_keys: :error` to reject unknown fields.

```elixir
defmodule Orders.CancelOrder do
  alias Jido.Joi

  use Jido.Action,
    name: "cancel_order",
    schema: Joi.object(%{order_id: Joi.string()}, unrecognized_keys: :error)

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:error, %Jido.Error.ValidationError{message: "unrecognized key: reason"}} =
  Orders.CancelOrder.validate_params(%{order_id: "o-1", reason: "duplicate"})

{:ok, %{quantity: 1, note: "kept"}} =
  Orders.SetQuantity.validate_params(%{quantity: 1, note: "kept"})
```

## Use a struct schema

`Jido.Joi.struct/3` builds a closed schema. Set `coerce: true` so it accepts a plain map. The Action receives a plain map, not the struct, because Jido converts parsed struct results at the Action boundary.

```elixir
defmodule Orders.Address do
  defstruct [:city, :postal_code]
end

defmodule Orders.SetAddress do
  alias Jido.Joi

  use Jido.Action,
    name: "set_address",
    schema:
      Joi.struct(
        Orders.Address,
        %{city: Joi.string(), postal_code: Joi.string()},
        coerce: true
      )

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:ok, %{city: "Oslo", postal_code: "0150"} = address} =
  Orders.SetAddress.validate_params(%{city: "Oslo", postal_code: "0150"})

false = is_struct(address)
```

Without `coerce: true`, a plain map fails with `invalid type: expected struct`.

## Add custom rules with named functions

Schemas are static module data. Refinements and transforms must use `{Module, :function, args}` tuples. An anonymous function or a `Jido.Joi.lazy/1` schema stops compilation.

A refinement function receives the value, then the listed `args`, then an options list. It returns `:ok` or `{:error, message}`. A transform receives the value and options and returns the new value.

```elixir
defmodule Orders.ReserveStock do
  alias Jido.Joi

  use Jido.Action,
    name: "reserve_stock",
    schema:
      Joi.object(%{
        sku:
          Joi.string()
          |> Joi.refine({__MODULE__, :has_prefix, ["SKU-"]})
          |> Joi.transform({__MODULE__, :normalize, []})
      })

  def has_prefix(value, prefix, _opts) do
    if String.starts_with?(value, prefix),
      do: :ok,
      else: {:error, "must start with #{prefix}"}
  end

  def normalize(value, _opts), do: String.upcase(value)

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:ok, %{sku: "SKU-A1"}} = Orders.ReserveStock.validate_params(%{sku: "SKU-a1"})

{:error, %Jido.Error.ValidationError{message: "must start with SKU-, at sku"}} =
  Orders.ReserveStock.validate_params(%{sku: "a1"})
```

The schema expression can call functions. It is evaluated once, during compilation.

## Prepare raw input

Implement `on_before_validate_params/1` when a rule must run before Joi sees the value. Prefer coercion, defaults, enums, and refinements when they can express the rule. The callback returns `{:ok, params}` or `{:error, reason}`. Keep it deterministic.

```elixir
defmodule Orders.FindCustomer do
  alias Jido.Joi

  use Jido.Action,
    name: "find_customer",
    schema: Joi.object(%{email: Joi.string()})

  @impl true
  def on_before_validate_params(%{"email" => email}) when is_binary(email) do
    {:ok, %{email: email |> String.trim() |> String.downcase()}}
  end

  def on_before_validate_params(params), do: {:ok, params}

  @impl true
  def run(params, _context), do: {:ok, params}
end

{:ok, %{email: "ana@example.com"}} =
  Jido.Exec.run(Orders.FindCustomer, %{"email" => " Ana@Example.com "})
```

## Validate output

`:output_schema` uses the same rules as `:schema`, and it can change the result. Defaults are added, transforms run, and open schemas keep other fields. The caller receives the validated map.

```elixir
defmodule Orders.ShipOrder do
  alias Jido.Joi

  use Jido.Action,
    name: "ship_order",
    output_schema:
      Joi.object(%{
        tracking_id: Joi.string(),
        carrier: Joi.string() |> Joi.default("standard")
      })

  @impl true
  def run(%{tracking_id: tracking_id}, _context), do: {:ok, %{tracking_id: tracking_id, weight_kg: 2}}
  def run(_params, _context), do: {:ok, %{carrier: "air"}}
end

{:ok, %{tracking_id: "t-1", carrier: "standard", weight_kg: 2}} =
  Jido.Exec.run(Orders.ShipOrder, %{tracking_id: "t-1"})

{:error, %Jido.Error.ValidationError{message: "is required, at tracking_id"}} =
  Jido.Exec.run(Orders.ShipOrder, %{})
```

Effects are not validated by `:output_schema`. Output validation failure returns no effects. A `Jido.Action.Output` envelope skips the output schema unless its kind is `:preserve`. See [Outputs and Effects](action-effects.livemd).

## Read validation errors

Validation returns `Jido.Error.ValidationError`. `details.errors` lists every issue with its code, message, and data path. The exception message joins them, one per line.

```elixir
{:error, error} =
  Orders.CreateOrder.validate_params(%{
    customer_id: "",
    channel: :fax,
    lines: [%{sku: "A-1", quantity: 0}]
  })

%Jido.Error.ValidationError{details: %{module: Orders.CreateOrder, context: "Action"}} = error

true = %{code: :invalid_enum_value, path: [:channel], message: "invalid enum value: expected one of web, phone"} in error.details.errors
true = Enum.any?(error.details.errors, &(&1.path == [:lines, 0, :quantity]))

false = Jido.Error.retryable?(error)
```

Use `code` and `path` in program logic. Validation errors are not retryable by default, so `max_attempts` does not repeat them.

## Compile-time checks

`use Jido.Action` rejects these configurations with a `CompileError`:

| Configuration | Message contains |
|---|---|
| Missing `:name` | `is required, at name` |
| Blank, non-UTF-8, or over 256 byte name | The specific rule, at `name` |
| Unknown option | `unrecognized key` |
| A schema that does not accept map data, such as `Jido.Joi.string()` | `must accept map-shaped data` |
| A value that is not a Joi schema | `must be a Joi schema` |
| An anonymous function in a schema | `must be static module data` |
| A pid, port, or reference in a schema | `must be static module data` |

## JSON Schema projection

`authoring_contract/0` projects both schemas with `Jido.Joi.to_json_schema/1`. The projection has limits to check before you give it to another system:

- A field with `Jido.Joi.default/2` appears in `required`, although validation accepts input that omits it.
- Refinements and transforms do not appear in the projection.
- A schema with no JSON Schema form makes `authoring_contract/0` raise `ArgumentError`.

## Related

- [Actions](actions.md)
- [Outputs and Effects](action-effects.livemd)
- [Jido.Joi Validation](../data/joi-validation.md)
