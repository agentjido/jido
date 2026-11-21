# Flow Errors

This reference lists how Flow runs fail, what each error contains, and which failures Jido retries.

Every failure from `Jido.Exec.run/4` is `{:error, error}`, and `error` is an exception struct from `Jido.Error`. A failed run returns no effects, including effects from steps that already succeeded.

## Match on structure

Match on the struct and on `details`. Messages are for people and can change. `details.reason` is the field most failures set for programs.

```elixir
defmodule FlowErrorsGuide.ChargeCard do
  use Jido.Action, name: "flow_errors_guide_charge_card"

  @impl true
  def run(%{cents: cents}, _context) when cents > 50_000 do
    {:error, Jido.Error.execution_error("card declined", %{reason: :card_declined, retry: false})}
  end

  def run(%{cents: cents}, _context), do: {:ok, %{charged: cents}, [{:send_receipt, cents}]}
end

defmodule FlowErrorsGuide.Checkout do
  use Jido.Flow,
    name: "flow_errors_guide_checkout",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  flow do
    step "charge", action: FlowErrorsGuide.ChargeCard, params: %{cents: input(:cents)}
    output result("charge")
  end
end

outcome = fn input ->
  case Jido.Exec.run(FlowErrorsGuide.Checkout, input) do
    {:ok, output, _effects} -> {:charged, output.charged}
    {:error, %Jido.Error.ExecutionError{details: %{reason: :card_declined, node: node}}} -> {:declined, node}
    {:error, %Jido.Error.ValidationError{details: %{phase: :flow_input}}} -> :bad_request
    {:error, error} -> {:failed, Jido.Error.type(error)}
  end
end

{:charged, 1_000} = outcome.(%{cents: 1_000})
{:declined, "charge"} = outcome.(%{cents: 90_000})
:bad_request = outcome.(%{cents: "many"})
```

## Error types

`Jido.Error.type/1` returns the atom in the right column.

| Struct | Raised for | `Jido.Error.type/1` |
| --- | --- | --- |
| `Jido.Error.ValidationError` | Invalid Flow input, Action params, Action or Flow output | `:validation_error` |
| `Jido.Error.ValidationError` with `kind: :config` | Bad options, an unknown target, a host that cannot run waits | `:config_error` |
| `Jido.Error.ExecutionError` | Action failures, reference failures, loop limits | `:execution_error` |
| `Jido.Error.TimeoutError` | An attempt ran past `:timeout`. The limit is in `error.timeout` | `:timeout` |
| `Jido.Error.InternalError` | A validator returned a value outside its contract | `:internal` |

## Failure catalog

| Failure | Error | Identifying fields |
| --- | --- | --- |
| Flow input fails the Flow `schema` | `ValidationError` | `details.phase: :flow_input`, `details.errors` |
| Action params fail its `schema` | `ValidationError` | `details.errors`, `details.module` |
| Flow output fails `output_schema` | `ValidationError` | `details.phase: :flow_output`, `details.errors` |
| Flow output is not a map | `ValidationError` | `message: "Action output validation must return a map"` |
| Action returns `{:error, reason}` with a non-exception reason | `ExecutionError` | `details.reason`, `details.action`, `phase: :run` |
| Action returns `{:error, exception}` | That exception | Its own fields |
| Action raises | `ExecutionError` | `details.exception`, `details.stacktrace`, `phase: :run` |
| Action throws or exits | `ExecutionError` | `message` of `"Action run throw"` or `"Action run exit"`, `details.reason` |
| Action returns another value | `ExecutionError` | `details.reason: :invalid_return`, `details.return` |
| Effects are not a proper list | `ExecutionError` | `details.reason: :invalid_effects` |
| Action outside Invoke or Handoff returns a control tuple | `ExecutionError` | `details.reason` of `:unsupported_continuation` or `:unsupported_handoff` |
| Handoff selector returns no `{:handoff, input, target}` | `ExecutionError` | `details.reason: :invalid_handoff_return` |
| A reference path is missing | `ExecutionError` | `details.reason: :missing_key`, `details.ref_type`, `details.path`, `retry: false` |
| Attempt exceeds `:timeout` | `TimeoutError` | `error.timeout` |
| Task exits, for example with `:kill` | `ExecutionError` | `phase: :execution_task`, `details.reason` |
| A Map item's `params` reference is missing, with `:fail_fast` | `ExecutionError` | `message: "flow reference path does not exist"`, with `details.node`, `details.node_path`, and `details.item_index` |
| Iterate runs out of attempts | `ExecutionError` | `message: "flow iterator exhausted maximum iterations"` |
| Waits under `Jido.Exec.run/4` | `ValidationError` | `details.reason: :unsupported_host`, `details.capability: :waits` |
| Action code changes after the graph is built | `ValidationError` | `details.reason: :incompatible_target` |
| Durable data holds a PID, port, reference, or function | `ExecutionError` | `details.reason: :non_portable_durable_value`, `details.type`, `details.path` |

An Action can also return `{:error, reason, effects}`. Jido keeps the error and drops those effects.

## Position fields

Jido adds position fields to errors raised inside a Flow component, so you can find the failing item without logging.

| Field | Set for | Meaning |
| --- | --- | --- |
| `details.node` | All components | The component name |
| `details.node_path` | All components | The path from the root Flow, for example `["checks", "stock"]` |
| `details.source` | Module DSL Flows | `%{file: path, line: n}` of the declaration |
| `details.item_index`, `details.item_id` | Map, Reduce | The item position and its stable ID |
| `details.action_index`, `details.action_name` | Parallel | The named Action inside the component |
| `details.iteration_index`, `details.state_revision` | Iterate | The iteration that failed |

A failure in the Flow `output` has no component, so it carries `details.phase: :flow_output` in place of `details.node`.

## Collect errors instead of failing fast

Map and Parallel use `on_error: :fail_fast` by default. A failure fails the run and no new work starts. Items already running can finish. When several fail, the run reports the one with the lowest position. Use `:collect_errors` to keep going and read each outcome from the result.

```elixir
defmodule FlowErrorsGuide.BillAccount do
  use Jido.Action, name: "flow_errors_guide_bill_account"

  @impl true
  def run(%{account: "closed"}, _context) do
    {:error, Jido.Error.execution_error("account closed", %{reason: :account_closed, retry: false})}
  end

  def run(%{account: account}, _context), do: {:ok, %{billed: account}}
end

defmodule FlowErrorsGuide.BillRun do
  use Jido.Flow, name: "flow_errors_guide_bill_run"

  flow do
    map "bills",
      collection: input(:accounts),
      action: FlowErrorsGuide.BillAccount,
      params: %{account: item()},
      on_error: :collect_errors

    output %{bills: result("bills")}
  end
end

{:ok, %{bills: [billed, failed]}} = Jido.Exec.run(FlowErrorsGuide.BillRun, %{accounts: ["acme", "closed"]})

%{status: :ok, value: %{billed: "acme"}} = billed

%{
  status: :error,
  error: %{
    type: :execution_error,
    message: "account closed",
    retryable?: false,
    details: %{reason: :account_closed, node: "bills", item_index: 1}
  }
} = failed
```

The result shape changes with the mode:

| Component | `:fail_fast` item | `:collect_errors` item |
| --- | --- | --- |
| Map | The Action output | `%{status: :ok, value: output}` or `%{status: :error, error: map}` |
| Parallel | `%{name: name, value: output}` | The Map form plus `name` |

Each collected error is a plain map from `Jido.Error.to_map/1` without a stacktrace, not an exception struct. Parallel error details also carry `action_index` and `action_name`. Effects from the successful items are kept.

In Parallel, set the mode inside the block:

<!-- partial -->
```elixir
parallel "checks" do
  on_error :collect_errors
  action "stock", CheckStock, params: %{sku: input(:sku)}
  action "fraud", CheckFraud, params: %{order_id: input(:order_id)}
end
```

## Retries

Set `:max_attempts` to retry. Jido calls `Jido.Error.retryable?/1` on each failure.

| Error | Retried by default |
| --- | --- |
| Validation and config errors | No |
| `ExecutionError`, including raises and plain `{:error, reason}` returns | Yes |
| `TimeoutError` | Yes |
| `InternalError` | Yes |
| Missing reference | No, it sets `retry: false` |

Set a `:retry`, `:retryable`, or `:retryable?` Boolean in `details` to override the default.

Retry is the default for execution failures, including raises. A retried Action runs again from the start. If it charges a card or sends a message, make the Action idempotent, or return `retry: false` once the outside system has seen the request. A timed-out attempt may also have reached that system before it stopped.

```elixir
final = Jido.Error.execution_error("card declined", %{reason: :card_declined, retry: false})
transient = Jido.Error.execution_error("gateway busy", %{reason: :busy})

false = Jido.Error.retryable?(final)
true = Jido.Error.retryable?(transient)
```

## Convert for logs and transport

`Jido.Error.to_map/1` returns `%{type: _, message: _, details: _, retryable?: _}` with sanitized, size-limited details. Use it at a process or network boundary.

```elixir
%{type: :execution_error, message: "card declined", retryable?: false, details: %{reason: :card_declined}} =
  Jido.Error.to_map(final)
```

`Jido.Error.code/1` reads a stable program code. Codes cover Agent, Plugin, persistence, and configuration failures, and `Jido.Error.stable_codes/0` lists them. Flow failures such as those above have no code, so `code/1` returns `nil`. Use `details.reason` for those.

## Runic observation errors

`Jido.Exec.result/2` returns the same errors as `Jido.Exec.run/4`, plus these states for work that has not finished cleanly. All are `ExecutionError`.

| `details.reason` | Meaning |
| --- | --- |
| `:execution_active` | Work is still running or ready. Read the result again later |
| `:admission_stopped` | A failure stopped new work. No failure was recorded for this input |
| `:foreign_execution` | The workflow has a result, but for another input |
| `details.outcome: :uncertain` | The executor ended with no result. The Action may or may not have run |

See [Direct Runic Execution](managed-execution.md) and [Debug Flows](debugging-flows.md#inspect-a-direct-runic-run).

## Next steps

- [Debug Flows](debugging-flows.md) shows how to find the cause of a failure.
- [Test Flows](testing-flows.livemd) asserts on these errors.
