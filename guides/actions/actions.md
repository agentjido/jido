# Actions

This guide shows how to define an Action, run it, and handle its result. An Action is one named unit of work with a validated input and a validated output.

## Define an Action

Use `Jido.Action` in a module, declare its schemas, and implement `run/2`.

```elixir
defmodule Billing.CalculateInvoiceTotal do
  alias Jido.Joi

  use Jido.Action,
    name: "calculate_invoice_total",
    description: "Adds tax to an invoice subtotal",
    schema:
      Joi.object(%{
        subtotal_cents: Joi.integer() |> Joi.min(0),
        tax_rate: Joi.float() |> Joi.default(0.1)
      }),
    output_schema: Joi.object(%{total_cents: Joi.integer()})

  @impl true
  def run(params, _context) do
    {:ok, %{total_cents: round(params.subtotal_cents * (1 + params.tax_rate))}}
  end
end
```

`run/2` receives the validated input and a context map. See [Action Context](action-context.md) for the second argument.

`use Jido.Action` accepts these options. Any other key stops compilation.

| Option | Required | Default | Purpose |
|---|---|---|---|
| `:name` | yes | none | Non-blank UTF-8 string of at most 256 bytes |
| `:description` | no | `nil` | String that describes the Action |
| `:schema` | no | `Jido.Joi.map()` | Input schema |
| `:output_schema` | no | `Jido.Joi.map()` | Output schema |
| `:id` | no | The module name as a string | Stable identifier for authoring discovery |
| `:vsn` | no | `1` | Positive integer authoring version |

A module without `run/2` does not compile. [Schemas and Validation](schemas-validation.md) covers schema rules.

The macro generates `name/0`, `description/0`, `schema/0`, `output_schema/0`, `authoring_contract/0`, `validate_params/1`, and `validate_output/1`.

```elixir
"calculate_invoice_total" = Billing.CalculateInvoiceTotal.name()
"Adds tax to an invoice subtotal" = Billing.CalculateInvoiceTotal.description()
```

## Run an Action

Call `Jido.Exec.run/4` with the target, the parameters, the context, and the execution options. The last three are optional. Parameters and context can be maps, keyword lists, or `nil`.

```elixir
{:ok, %{total_cents: 110}} =
  Jido.Exec.run(Billing.CalculateInvoiceTotal, %{subtotal_cents: 100})

{:ok, %{total_cents: 120}} =
  Jido.Exec.run(Billing.CalculateInvoiceTotal, subtotal_cents: 100, tax_rate: 0.2)
```

`Jido.Exec.run/4` validates the input, calls `run/2`, validates the output, and converts failures to error values. It runs the work in a supervised task, so an Action that crashes does not take down the caller.

Invalid input stops before `run/2` is called:

```elixir
{:error, %Jido.Error.ValidationError{} = error} =
  Jido.Exec.run(Billing.CalculateInvoiceTotal, %{subtotal_cents: -1})

"too small: must be at least 0, at subtotal_cents" = Exception.message(error)
```

## Choose how to call an Action

| Call | Process | Validates | Timeout and retry | Use it when |
|---|---|---|---|---|
| `Jido.Exec.run/4` | Supervised task | Yes | Yes | You want the public execution boundary. This is the default. |
| `run/2` on the module | Caller | No | No | You test the function body or validate each boundary yourself. |

Actions and Flows use the same `Jido.Exec.run/4` path. Exec compiles one
Action as a one-step Flow and isolates it from the caller.

A direct `run/2` call skips schema defaults, so validate first:

```elixir
{:ok, params} = Billing.CalculateInvoiceTotal.validate_params(%{subtotal_cents: 100})
{:ok, output} = Billing.CalculateInvoiceTotal.run(params, %{})
{:ok, %{total_cents: 110}} = Billing.CalculateInvoiceTotal.validate_output(output)
```

## Return a result

`run/2` returns one of these values. The table shows what `Jido.Exec.run/4` gives the caller.

| `run/2` returns | `Jido.Exec.run/4` returns |
|---|---|
| `{:ok, map}` | `{:ok, validated_map}` |
| `{:ok, map, []}` | `{:ok, validated_map}` |
| `{:ok, map, effects}` | `{:ok, validated_map, effects}` |
| `{:ok, %Jido.Action.Output{}}` | `{:ok, envelope}`, see [Outputs and Effects](action-effects.livemd) |
| `{:error, exception}` | `{:error, exception}` |
| `{:error, reason}` | `{:error, %Jido.Error.ExecutionError{}}` |
| `{:error, reason, effects}` | The same error, with the effects discarded |

An Invoke expander can also return `{:continue, input, target}`, and a Handoff selector can return `{:handoff, input, target}`. A root Action that returns either one gets an error. See [Dynamic Flows](../flows/dynamic-flows.md).

## Handle failures

`Jido.Exec.run/4` returns an exception struct in every failure case. Match on the struct and read its fields. Do not match on the message.

```elixir
defmodule Billing.ChargeCard do
  use Jido.Action, name: "charge_card"

  @impl true
  def run(%{card: "expired"}, _context), do: {:error, :card_expired}
  def run(%{card: "stolen"}, _context), do: raise(ArgumentError, "card reported stolen")
  def run(%{card: "limit"}, _context) do
    {:error, Jido.Error.execution_error("over limit", %{retry: false, limit_cents: 500})}
  end

  def run(%{card: "gateway_bug"}, _context), do: :charged
  def run(_params, _context), do: {:ok, %{charged: true}}
end

{:error, %Jido.Error.ExecutionError{phase: :run, details: %{reason: :card_expired}}} =
  Jido.Exec.run(Billing.ChargeCard, %{card: "expired"})

{:error, %Jido.Error.ExecutionError{phase: :run, details: %{exception: ArgumentError}}} =
  Jido.Exec.run(Billing.ChargeCard, %{card: "stolen"})

{:error, %Jido.Error.ExecutionError{details: %{limit_cents: 500}}} =
  Jido.Exec.run(Billing.ChargeCard, %{card: "limit"})

{:error, %Jido.Error.ExecutionError{details: %{reason: :invalid_return}}} =
  Jido.Exec.run(Billing.ChargeCard, %{card: "gateway_bug"})
```

| Failure | Error |
|---|---|
| Input does not match `:schema` | `Jido.Error.ValidationError` |
| Output does not match `:output_schema`, or is not a map | `Jido.Error.ValidationError` |
| `{:error, exception}` | That exception, unchanged |
| `{:error, reason}` | `Jido.Error.ExecutionError` with `phase: :run` and `details.reason` |
| A raise | `Jido.Error.ExecutionError` with `phase: :run` and `details.exception` |
| A throw or exit in `run/2` | `Jido.Error.ExecutionError` with `phase: :run`, `details.kind`, and `details.reason` |
| A return value outside the table above | `Jido.Error.ExecutionError` with `details.reason` set to `:invalid_return` |
| The task is killed | `Jido.Error.ExecutionError` with `phase: :execution_task` |
| The timeout expires | `Jido.Error.TimeoutError` |

`Jido.Error.to_map/1` projects any of these to `type`, `message`, `details`, and `retryable?`. See [Jido Error Contracts](../data/error-contracts.md).

## Keep an Action focused

An Action can be pure or can perform I/O. Give each Action one unit of work. Put composition in a Flow. Leave timeouts, retries, and persistence to the caller, so that the same Action works under different policies. See [Execution Policy](action-execution-policy.md).

## Use an Action in a Flow or Agent

A Flow calls an Action from a step:

```elixir
defmodule Billing.InvoiceFlow do
  use Jido.Flow,
    name: "invoice_flow",
    schema: Jido.Joi.object(%{subtotal_cents: Jido.Joi.integer()})

  flow do
    step "total",
      action: Billing.CalculateInvoiceTotal,
      params: %{subtotal_cents: input(:subtotal_cents)}

    output result("total")
  end
end

{:ok, %{total_cents: 110}} = Jido.Exec.run(Billing.InvoiceFlow, %{subtotal_cents: 100})
```

An Agent route can name an Action as its handler. In that position the Action output is the complete next Agent state. See [Routes and Handlers](../agents/build-agent-routes.livemd).

## Publish the Action contract

`authoring_contract/0` returns the Action metadata and JSON Schema projections of both schemas as JSON-safe data.

```elixir
%{
  "id" => "Elixir.Billing.CalculateInvoiceTotal",
  "kind" => "action",
  "name" => "calculate_invoice_total",
  "vsn" => 1,
  "input_schema" => %{"type" => "object"},
  "output_schema" => %{"properties" => %{"total_cents" => %{"type" => "integer"}}}
} = Billing.CalculateInvoiceTotal.authoring_contract()
```

The function raises `ArgumentError` when a schema has no JSON Schema form. Validation and execution still work in that case.

## Next steps

- [Schemas and Validation](schemas-validation.md)
- [Outputs and Effects](action-effects.livemd)
- [Execution Policy](action-execution-policy.md)
- [Test Actions](testing-actions.livemd)
