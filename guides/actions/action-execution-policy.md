# Execution Policy

This guide lists the options that bound one Action run: timeouts, retries, backoff, and the owning process. The caller sets policy at each `Jido.Exec.run/4` call. An Action does not declare it.

## Options

| Option | Default | Allowed values | Meaning |
|---|---|---|---|
| `:timeout` | `:infinity` | Non-negative integer, or `:infinity` | Milliseconds allowed for each attempt |
| `:max_attempts` | `1` | Positive integer | Total attempts, including the first |
| `:backoff` | `:none` | `:none`, `:linear`, `:exponential`, `:jitter` | Delay rule between attempts |
| `:base_delay_ms` | `0` | Non-negative integer | Base for the delay rule |
| `:max_delay_ms` | `0` | Non-negative integer | Upper limit for every delay |
| `:max_concurrency` | See [Concurrency](#concurrency) | Positive integer | Concurrent Flow work. No effect on one Action. |
| `:task_supervisor` | The Jido application task supervisor | Local pid, registered name, or `{:via, module, name}` | Owner of the execution task. `Jido.Exec.run/4` only. |

Options apply to `Jido.Exec.run/4`. An unknown or invalid option returns a configuration error, and no work runs.

```elixir
defmodule Payments.Ping do
  use Jido.Action, name: "ping"

  @impl true
  def run(_params, _context), do: {:ok, %{pong: true}}
end

{:error, %Jido.Error.ValidationError{message: "unknown execution options", details: %{options: [:retries]}}} =
  Jido.Exec.run(Payments.Ping, %{}, %{}, retries: 3)

{:error, %Jido.Error.ValidationError{message: "max_attempts must be a positive integer"}} =
  Jido.Exec.run(Payments.Ping, %{}, %{}, max_attempts: 0)
```

## Set a timeout

The timeout applies to each attempt, not to the whole run. When it expires, Exec kills the attempt's process and returns `Jido.Error.TimeoutError`.

```elixir
defmodule Payments.WaitForGateway do
  use Jido.Action, name: "wait_for_gateway"

  @impl true
  def run(_params, _context) do
    receive do
      :gateway_replied -> {:ok, %{settled: true}}
    end
  end
end

{:error, %Jido.Error.TimeoutError{timeout: 20}} =
  Jido.Exec.run(Payments.WaitForGateway, %{}, %{}, timeout: 20)
```

`timeout: 0` fails without running the Action.

Killing the process does not undo work already done. A request sent to another system can still complete. A process that the Action started without a link can keep running, and the caller must clean it up.

In a Flow, the timeout applies to each attempt of each Action, so the whole Flow can run longer than the value. A timed-out Action can also stop before it emits its telemetry stop event.

## Retry a failure

`:max_attempts` counts the first attempt. Exec retries only when `Jido.Error.retryable?/1` returns `true` for the error.

```elixir
defmodule Payments.ChargeWithRetry do
  use Jido.Action, name: "charge_with_retry"

  @impl true
  def run(%{succeed_on: succeed_on}, %{attempts: attempts}) do
    :counters.add(attempts, 1, 1)
    attempt = :counters.get(attempts, 1)

    if attempt < succeed_on do
      {:error, Jido.Error.execution_error("gateway unavailable")}
    else
      {:ok, %{attempt: attempt}}
    end
  end
end

attempts = :counters.new(1, [])

{:ok, %{attempt: 3}} =
  Jido.Exec.run(Payments.ChargeWithRetry, %{succeed_on: 3}, %{attempts: attempts}, max_attempts: 3)
```

Without `:max_attempts`, an Action runs once.

Retries run `run/2` again from the start, with the same input. Any side effect in `run/2` can repeat, so make it idempotent or return it as an effect request. See [Outputs and Effects](action-effects.livemd). Effects from failed attempts are never returned.

### Which errors retry

| Failure | Default |
|---|---|
| Input or output validation error | Not retried |
| Configuration error | Not retried |
| `{:error, reason}` | Retried |
| A raise, throw, or exit in `run/2` | Retried |
| An invalid return value from `run/2` | Retried |
| `Jido.Error.TimeoutError` | Retried |
| `Jido.Error.InternalError` | Retried |

The default favors retrying, so state your intent for a permanent failure. A `:retry`, `:retryable`, or `:retryable?` boolean overrides the default. Jido looks for it on the error, in `details`, and in a map `reason`.

```elixir
defmodule Payments.DeclineCard do
  use Jido.Action, name: "decline_card"

  @impl true
  def run(_params, %{attempts: attempts}) do
    :counters.add(attempts, 1, 1)
    {:error, Jido.Error.execution_error("card declined", %{retry: false})}
  end
end

attempts = :counters.new(1, [])

{:error, %Jido.Error.ExecutionError{message: "card declined"} = error} =
  Jido.Exec.run(Payments.DeclineCard, %{}, %{attempts: attempts}, max_attempts: 5)

1 = :counters.get(attempts, 1)
false = Jido.Error.retryable?(error)
```

## Add backoff

Set `:backoff`, `:base_delay_ms`, and `:max_delay_ms` together. Both delay options default to `0`, and every delay is capped at `:max_delay_ms`. If you set `:base_delay_ms` alone, the delay stays `0`.

`attempt` starts at `0` for the delay after the first attempt.

| `:backoff` | Delay before the next attempt |
|---|---|
| `:none` | `0` |
| `:linear` | `min(base_delay_ms * (attempt + 1), max_delay_ms)` |
| `:exponential` | `min(base_delay_ms * 2 ** attempt, max_delay_ms)` |
| `:jitter` | `min(random(1..base_delay_ms * 2 ** attempt), max_delay_ms)` |

```elixir
attempts = :counters.new(1, [])

{elapsed_microseconds, {:ok, %{attempt: 3}}} =
  :timer.tc(fn ->
    Jido.Exec.run(Payments.ChargeWithRetry, %{succeed_on: 3}, %{attempts: attempts},
      max_attempts: 3,
      backoff: :exponential,
      base_delay_ms: 10,
      max_delay_ms: 15
    )
  end)

true = elapsed_microseconds >= 25_000
```

This run waits `10` ms, then `15` ms, because `20` is capped at `15`.

The delay blocks the execution task. `:timeout` does not limit it, because it applies to each attempt.

## Process ownership

`Jido.Exec.run/4` runs the Action in an unlinked temporary task:

- A crash or kill in the Action returns an error. It does not exit the caller.
- The task keeps the caller's group leader, so `IO` output goes to the same place.
- If the caller exits, Jido kills the task and the processes linked to it.
- The Jido application task supervisor owns the task unless you pass `:task_supervisor`.

```elixir
defmodule Payments.CrashingCharge do
  use Jido.Action, name: "crashing_charge"

  @impl true
  def run(_params, _context), do: Process.exit(self(), :kill)
end

{:error, %Jido.Error.ExecutionError{phase: :execution_task, details: %{reason: :killed}}} =
  Jido.Exec.run(Payments.CrashingCharge)
```

Pass your own supervisor to bound or isolate work. It must be a running local process. A supervisor that is not running returns an error without running the Action.

```elixir
{:ok, payments_tasks} = Task.Supervisor.start_link()

{:ok, %{pong: true}} = Jido.Exec.run(Payments.Ping, %{}, %{}, task_supervisor: payments_tasks)

{:error, %Jido.Error.ValidationError{message: "Task Supervisor is not running"}} =
  Jido.Exec.run(Payments.Ping, %{}, %{}, task_supervisor: :no_such_supervisor)
```

## Concurrency

`:max_concurrency` limits concurrent work inside a Flow, including nested and collection work. Reduce and Iterate stay serial. A single Action ignores it after validation.

The default is the `:max_concurrency` value in the `:jido` application environment. Without that, it is the smaller of `System.schedulers_online/0` and `10`.

<!-- partial -->
```elixir
# config/runtime.exs
config :jido, max_concurrency: 4
```

## Apply policy in a Flow

Policy passed to `Jido.Exec.run/4` applies to every Action in the Flow. A retry repeats only the failing Action, and completed steps do not run again.

```elixir
defmodule Payments.CaptureStep do
  use Jido.Action, name: "capture_step"

  @impl true
  def run(%{slot: slot, succeed_on: succeed_on}, %{attempts: attempts}) do
    :counters.add(attempts, slot, 1)

    if :counters.get(attempts, slot) < succeed_on,
      do: {:error, "gateway unavailable"},
      else: {:ok, %{slot: slot}}
  end
end

defmodule Payments.CaptureFlow do
  use Jido.Flow, name: "capture_flow"

  flow do
    step "authorize", action: Payments.CaptureStep, params: %{slot: 1, succeed_on: 1}

    step "capture",
      action: Payments.CaptureStep,
      params: %{slot: 2, succeed_on: 3},
      needs: ["authorize"]

    output result("capture")
  end
end

attempts = :counters.new(2, [])

{:ok, %{slot: 2}} = Jido.Exec.run(Payments.CaptureFlow, %{}, %{attempts: attempts}, max_attempts: 3)

1 = :counters.get(attempts, 1)
3 = :counters.get(attempts, 2)
```

An Agent passes options other than `:context` from `cmd/3` to `Jido.Exec.run/4`.

Long-running work that must survive the caller belongs under `Jido.Exec.start/6`, which takes the same policy options and more worker options. See [Managed Execution](../flow-runtime/managed-execution.md).

## Observe attempts

Each attempt emits `[:jido, :action, :start]` and `[:jido, :action, :stop]` telemetry events with its own `attempt_id`. The `attempt` metadata value starts at `0`. Normal errors complete the span with `outcome: :error`. See [Telemetry and Tracing](../operations/telemetry-tracing-and-logs.md).

## Related

- [Actions](actions.md)
- [Flow Errors](../flow-runtime/flow-errors.md)
- [Test Actions](testing-actions.livemd)
