# Expressions

This reference lists the operators a Flow field can use, how they evaluate, how they fail, and their limits. `Jido.Expr` implements them as a closed set of inert data operations.

Use an expression for a small calculation or a condition. It cannot call application functions, and it contains no executable callbacks. Put other logic in an Action or an inline body.

## Write an expression

Write the operators directly in `params`, `output`, a condition, or another value field. References and literals can be operands.

```elixir
defmodule FlowExpr.Echo do
  use Jido.Action, name: "flow_expr_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule FlowExpr.Invoice do
  use Jido.Flow, name: "flow_expr_invoice"

  flow do
    step "line",
      action: FlowExpr.Echo,
      params: %{
        subtotal: input(:quantity) * input(:unit_cents),
        label: "Invoice for " <> input(:customer)
      }

    output %{
      label: result("line", :label),
      total: result("line", :subtotal) + max(input(:fee), 0),
      taxable: input(:region) in ["EU", "UK"] and not input(:exempt)
    }
  end
end

{:ok, %{label: "Invoice for Ada", total: 3100, taxable: true}} =
  Jido.Exec.run(FlowExpr.Invoice, %{
    quantity: 3,
    unit_cents: 1000,
    fee: 100,
    customer: "Ada",
    region: "EU",
    exempt: false
  })
```

`expr(...)` is an optional wrapper in the Flow DSL with the same meaning.

## Operators

`Jido.Expr.operations/0` returns this closed list. The syntax follows Elixir precedence and grouping.

| Group | Operators | Operands | Notes |
| --- | --- | --- | --- |
| Equality | `==`, `!=` | Any data | Uses Elixir `==`, so `1 == 1.0` is true. |
| Ordering | `<`, `<=`, `>`, `>=` | Any data | Uses Elixir term order, including mixed types. |
| Membership | `in` | Any value, proper list | Uses strict `===`, so `1 in [1.0]` is false. `not in` also works. |
| Boolean | `and`, `or`, `not` | Boolean | See [Boolean rules](#boolean-rules). |
| Arithmetic | `+`, `-`, `*`, `/`, unary `-`, `abs/1` | Numbers | `/` always returns a float. |
| Integer | `div/2`, `rem/2` | Integers | |
| Selection | `min/2`, `max/2` | Any data | Uses Elixir term order. |
| Text | `<>` | Binaries | |

There is no implicit conversion. A number added to a numeric string fails.

The compiler rejects everything else, including tuples, ranges, `if`, `&&`, `||`, `===`, unary `+`, and function calls such as `String.trim(input(:name))`. The error reads "unsupported Flow expression".

## Boolean rules

`and` and `or` require a Boolean left operand, short-circuit, and return the evaluated right operand unchanged. `not` requires a Boolean.

```elixir
defmodule FlowExpr.Boolean do
  use Jido.Flow, name: "flow_expr_boolean"

  flow do
    step "noop", [] do
      {:ok, %{}}
    end

    output %{
      right_operand: input(:enabled) and input(:plan),
      skipped: input(:enabled) or input(:not_supplied)
    }
  end
end

{:ok, %{right_operand: "pro", skipped: true}} =
  Jido.Exec.run(FlowExpr.Boolean, %{enabled: true, plan: "pro"})
```

A skipped operand is not resolved, so the missing `:not_supplied` key in this example causes no error. A `result` reference in a skipped operand still creates a dependency. See [Flow Dependencies](flow-dependencies.livemd).

## Conditions and missing values

A condition appears in a Choice option or an Iterate `while`. The compiler accepts a Boolean literal, a reference, or an operation. It rejects other literals with "unsupported Flow condition".

At runtime, a condition must evaluate to `true` or `false`. `nil`, numbers, and strings fail, and nothing treats them as falsey. A missing key fails too, unless a short-circuit skips it.

To keep conditions safe:

1. Declare the field as a required `Jido.Joi.boolean/1` in the Flow's `schema`, or in the producing Action's `output_schema`.
2. Compare explicitly when a field can be `nil`, such as `input(:coupon) != nil`.

## Evaluation failures

An operand of the wrong type, a zero divisor, or a limit failure ends the component with a `Jido.Error.ExecutionError` whose message is "invalid Flow expression". Its `details` hold the failure:

```elixir
defmodule FlowExpr.Ratio do
  use Jido.Flow, name: "flow_expr_ratio"

  flow do
    step "noop", [] do
      {:ok, %{}}
    end

    output %{ratio: input(:paid) / input(:total)}
  end
end

{:ok, %{ratio: 0.5}} = Jido.Exec.run(FlowExpr.Ratio, %{paid: 1, total: 2})

{:error, %Jido.Error.ExecutionError{details: details}} =
  Jido.Exec.run(FlowExpr.Ratio, %{paid: 1, total: 0})

%{reason: :division_by_zero, operator: :/, expression_path: [:ratio]} = details
```

Common `reason` values are `:invalid_numeric_operands`, `:invalid_binary_operands`, `:invalid_boolean_operand`, `:invalid_membership_right_operand`, and `:division_by_zero`. `expression_path` locates the failure within the field. See [Flow Errors](../flow-runtime/flow-errors.md).

## Resource limits

Each expression has these limits per call. Exceeding one fails with its limit as the `reason`.

| Option | Default | Limit on |
| --- | --- | --- |
| `:max_depth` | 64 | Nested data or expression levels. |
| `:max_nodes` | 10,000 | Visited values, including resolved data and comparison work. |
| `:max_binary_bytes` | 1,048,576 | Cumulative bytes in visited binaries and generated results. |
| `:max_integer_bits` | 4,096 | Bits in each integer magnitude. |

Flow uses these defaults. Direct calls to `Jido.Expr.parse/2`, `Jido.Expr.normalize/2`, `Jido.Expr.reduce/4`, `Jido.Expr.validate/2`, and `Jido.Expr.evaluate/2` accept the options. A limit cannot exceed 1,048,576,000, and `:max_integer_bits` cannot exceed 1,048,576.

## Build expressions outside the DSL

`Jido.Expr.expr/1` builds expression data in plain Elixir. Use it with `Jido.Flow.Ref` in a map definition. `^variable` inserts a prebuilt value or reference from an Elixir variable.

```elixir
import Jido.Expr, only: [expr: 1]

quantity = Jido.Flow.Ref.input(:quantity)

flow =
  Jido.Flow.new!(%{
    name: "flow_expr_data",
    components: [
      %{
        kind: :step,
        name: "line",
        action: FlowExpr.Echo,
        params: %{doubled: expr(^quantity * 2)}
      }
    ],
    output: Jido.Flow.Ref.result("line")
  })

{:ok, %{doubled: 8}} = Jido.Exec.run(flow, %{quantity: 4})
```

Pins exist only in `expr/1` outside the Flow DSL. They are a trusted source-code boundary. Inside `flow do`, write the reference directly, as a pin raises a `CompileError`.

`expr/1` raises `Jido.Expr.Error` at compile time for unsupported source, including an application call inside a pin. `Jido.Expr.new/2` builds one operation and checks its operator and arity:

```elixir
{:ok, %Jido.Expr.Operation{operator: :+, operands: [1, 2]}} = Jido.Expr.new(:+, [1, 2])
{:error, %Jido.Expr.Error{reason: :unknown_operator}} = Jido.Expr.new(:pow, [2, 3])
```

Expressions also evaluate without a Flow:

```elixir
import Jido.Expr, only: [expr: 1]

{:ok, 7} = Jido.Expr.evaluate(expr(2 * 3 + 1))

{:error, %Jido.Expr.Error{reason: :invalid_numeric_operands, operator: :+}} =
  Jido.Expr.evaluate(expr(1 + "invoice"))

:ok = Jido.Expr.validate(expr(1 + 2))
```

`Jido.Expr.validate/2` checks the tree shape and limits. It does not run operations, so it does not find type errors that only appear at evaluation.

## Reuse the grammar in a host DSL

Another data-only DSL can use the same grammar with its own references. `Jido.Expr.parse/2` takes quoted source and a `:leaf_parser` for AST it does not recognize. `Jido.Expr.evaluate/2` takes a `:resolve` callback for the host values. These callbacks handle leaves only and cannot add operators.

```elixir
defmodule FlowExpr.Field do
  defstruct [:key]
end
```

```elixir
parse_field = fn
  {:field, _meta, [key]} when is_atom(key) -> {:ok, %FlowExpr.Field{key: key}}
  _other -> :error
end

{:ok, expression} =
  Jido.Expr.parse(quote(do: field(:amount) * 2 + 1), leaf_parser: parse_field)

:ok =
  Jido.Expr.validate(expression,
    validate_leaf: fn %FlowExpr.Field{key: key} ->
      if key in [:amount], do: :ok, else: {:error, {:unknown_field, key}}
    end
  )

{:ok, 19} =
  Jido.Expr.evaluate(expression,
    resolve: fn %FlowExpr.Field{key: key} -> Map.fetch(%{amount: 9}, key) end
  )
```

The `:resolve` callback in this example returns `{:ok, value}`. It can also return `{:error, error}`, which passes through unchanged. An unknown struct fails when no callback handles it. Resolved data is checked as data and is never evaluated as an expression. These callbacks are trusted host code and must be bounded.

## Related

- [References and Data](flow-references.livemd) covers the values an expression reads.
- [Choices and Conditions](flow-choices.md) uses conditions to route.
