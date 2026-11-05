# Iterate and State

Use `iterate` to call one Action in a bounded loop that keeps local state between calls. This guide covers a fixed count, a condition, state updates, and how a loop fails.

An Iterate works like this:

1. `state` sets the initial State.
2. Each call receives `params` built from the current State.
3. `update` builds the next State from the call's result.
4. `repeat` or `while` decides when the loop stops.

## Repeat a fixed count

```elixir
defmodule FlowIterate.Backoff do
  use Jido.Action, name: "flow_iterate_backoff"

  @impl true
  def run(%{delay_ms: delay_ms, attempt: attempt}, _context) do
    {:ok, %{delay_ms: delay_ms * 2, attempt: attempt}}
  end
end

defmodule FlowIterate.BackoffPlan do
  use Jido.Flow, name: "flow_iterate_backoff_plan"

  flow do
    iterate "plan" do
      state Jido.Joi.object(%{delay_ms: Jido.Joi.integer()}), initial: %{delay_ms: input(:base_ms)}
      action FlowIterate.Backoff
      params %{delay_ms: state(:delay_ms), attempt: iteration_index()}
      update %{delay_ms: body_result(:delay_ms)}
      repeat 3
    end

    output %{plan: result("plan")}
  end
end

{:ok,
 %{
   plan: %{
     kind: :jido_flow_iterate_result,
     iterations: 3,
     state: %{delay_ms: 800},
     output: %{delay_ms: 800, attempt: 2}
   }
 }} = Jido.Exec.run(FlowIterate.BackoffPlan, %{base_ms: 100})
```

The result holds the completed call count, the final State, and the latest body result.

Iterate fields go in a block.

## Continue while a condition is true

`while` is checked before each call. A `while` loop must also set `max_iterations`. If the condition is false at the start, the body never runs and `output` is `nil`.

```elixir
defmodule FlowIterate.PayDown do
  use Jido.Action, name: "flow_iterate_pay_down"

  @impl true
  def run(%{balance: balance, payment: payment}, _context) do
    {:ok, %{balance: max(balance - payment, 0)}}
  end
end

defmodule FlowIterate.PaymentPlan do
  use Jido.Flow, name: "flow_iterate_payment_plan"

  flow do
    iterate "payments" do
      state Jido.Joi.object(%{balance: Jido.Joi.integer()}), initial: %{balance: input(:balance)}
      action FlowIterate.PayDown
      params %{balance: state(:balance), payment: input(:payment)}
      while state(:balance) > 0
      max_iterations 6
    end

    output %{payments: result("payments")}
  end
end

{:ok, %{payments: %{iterations: 3, state: %{balance: 0}}}} =
  Jido.Exec.run(FlowIterate.PaymentPlan, %{balance: 250, payment: 100})

{:ok, %{payments: %{iterations: 0, state: %{balance: 0}, output: nil}}} =
  Jido.Exec.run(FlowIterate.PaymentPlan, %{balance: 0, payment: 100})
```

If the condition is still true when the loop reaches `max_iterations`, the Iterate fails without an extra call:

```elixir
{:error,
 %Jido.Error.ExecutionError{
   phase: :iterate_exhaustion,
   details: %{completed_iterations: 6, max_iterations: 6}
 }} = Jido.Exec.run(FlowIterate.PaymentPlan, %{balance: 900, payment: 100})
```

A condition must evaluate to a Boolean. See [Conditions and missing values](flow-expressions.md#conditions-and-missing-values).

## Pick one stop rule

Use exactly one form:

| Form | Meaning |
| --- | --- |
| `repeat n` | Runs exactly `n` calls. `n` is from 1 through 10,000. `max_iterations` is not allowed. |
| `while condition` with `max_iterations n` | Runs while the condition holds. `n` is from 1 through 10,000. |

Any other combination raises `CompileError`. The same applies to a count outside the range.

## State and update

`state` takes a static schema and an `initial` value, in keyword or field-block form. The schema is required in the DSL, and it validates the initial State and every replacement. `Jido.Joi.map/0` accepts any map.

- State must be a plain map. Anything else fails with "iterator initial state must resolve to a plain map".
- A value that fails the schema returns a `Jido.Error.ValidationError` with phase `:iterate_state_initial` or `:iterate_state_update`.
- `initial` can read `input`, `context`, and `result`, but not the local references below.

The `update` expression runs after each successful call. Its value replaces the State. Jido does not merge it. If you omit `update`, the next State is the complete body result, as in the `PaymentPlan` example above.

## Local references

These references are valid in `params`, `update`, and `while`:

| Reference | Value |
| --- | --- |
| `state(path)` | The current State. |
| `iteration_index()` | The zero-based index of the current call. In `while`, it equals the number of completed calls. |
| `body_result(path)` | In `params` and `while`, `nil` before the first call, then the latest body result. In `update`, the result of the call that just finished. |

`body_result(:field)` fails before the first call with `reason: :not_traversable`, because the body result is `nil`. In `while`, guard it with `body_result() == nil or body_result(:field) < 1`. In `params`, keep the value in State instead.

## Targets and scope

The body must be an Action module. A Flow module raises `CompileError` with "Flow component has the wrong target kind", and inline bodies are not supported. The body Action validates its own parameters with its own schema.

An Iterate is one component. Other components read only its final result, and a failed call fails the Iterate. Use `needs` and `meta` as in [Steps and Output](flow-steps.md).

## Data form

In a map definition, Iterate uses `completion` in place of `while` or `repeat`. `completion` is a stop condition, so the loop stops when it is true. A DSL `while condition` lowers to `completion: not condition`, and `repeat n` lowers to `completion: iteration_index() >= n` with `max_iterations: n`. See [Flow Data Definitions](../flow-data/flow-data.md).
