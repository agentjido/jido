# Execution

This guide explains how `Jido.Exec` runs an Action or Flow: which entry point to use, what comes back, which options apply, and which process does the work.

## Choose an entry point

| Function | Use it when | Runs in | Survives its caller |
| --- | --- | --- | --- |
| `Jido.Exec.run/4` | You want the result now | A task under Jido's task supervisor | No |
| `Jido.Exec.start/6` | You want a supervised run you can step, inspect, stop, or resume | A Worker under a `Runic.Runner` | Yes |
| An Agent route | The work belongs to an Agent Turn | The `Jido.AgentServer` Turn | Yes |

A generated Flow module also has `run/2`. It calls `Jido.Exec.run/4` with default options. One Action is compiled as a one-step Flow and uses the same execution path.

This guide covers immediate execution. See [Managed Execution](managed-execution.md) for `Jido.Exec.start/6` and [Flow Waits](flow-waits.md) for work that suspends.

## Run a target

```elixir
defmodule ExecutionGuide.PriceInvoice do
  use Jido.Action,
    name: "execution_guide_price_invoice",
    schema: Jido.Joi.object(%{hours: Jido.Joi.integer(), rate: Jido.Joi.integer()})

  @impl true
  def run(%{hours: hours, rate: rate}, _context), do: {:ok, %{total: hours * rate}}
end

defmodule ExecutionGuide.Invoice do
  use Jido.Flow, name: "execution_guide_invoice"

  flow do
    step "price", action: ExecutionGuide.PriceInvoice, params: %{hours: input(:hours), rate: context(:rate)}
    output %{total: result("price", :total), currency: context(:currency)}
  end
end

{:ok, %{total: 300}} =
  Jido.Exec.run(ExecutionGuide.PriceInvoice, %{hours: 2, rate: 150})

{:ok, %{total: 300, currency: "EUR"}} =
  Jido.Exec.run(ExecutionGuide.Invoice, %{hours: 2}, %{rate: 150, currency: "EUR"})
```

`Jido.Exec.run/4` accepts an Action module, a Flow module, a `Jido.Flow` value, or a `Jido.Instruction`. When the target is an Instruction, call-site params and context replace equal keys in it. Params and context can each be a map, a keyword list, or `nil`.

## Read the result

| Result | Meaning |
| --- | --- |
| `{:ok, output}` | Success with no effects |
| `{:ok, output, effects}` | Success with a non-empty effect list |
| `{:handoff, instruction, effects}` | A terminal Handoff selected a successor |
| `{:error, error}` | Failure. No effects are returned |

Match all the shapes your target can produce. A Flow gains the three-element form as soon as any successful component returns effects.

```elixir
defmodule ExecutionGuide.SendReceipt do
  use Jido.Action, name: "execution_guide_send_receipt"

  @impl true
  def run(%{total: total}, _context), do: {:ok, %{sent: true}, [{:email_receipt, total}]}
end

{:ok, %{sent: true}, [{:email_receipt, 300}]} =
  Jido.Exec.run(ExecutionGuide.SendReceipt, %{total: 300})
```

`Jido.Exec` returns effects to the caller and dispatches none of them. Your code decides what to do with each one. In a Flow, effects follow dependency order, then component name. A nested Flow keeps its parent's position, and collections use input or iteration order. Effects from earlier steps are dropped when a later step fails.

A Flow output must be a map or a `Jido.Action.Output`. Wrap a list such as a Map result: `output %{items: result("items")}`.

## Set policy options

`Jido.Exec.run/4` takes these options. Unknown options return a config error.

| Option | Default | Meaning |
| --- | --- | --- |
| `:timeout` | `:infinity` | Limit for each attempt, in milliseconds |
| `:max_attempts` | `1` | Total attempts, including the first |
| `:backoff` | `:none` | `:none`, `:linear`, `:exponential`, or `:jitter` |
| `:base_delay_ms` | `0` | Base delay between attempts |
| `:max_delay_ms` | `0` | Upper bound for the delay |
| `:max_concurrency` | See below | Limit on concurrent Flow work |
| `:task_supervisor` | Jido's task supervisor | A local PID, registered name, or `{:via, module, name}` |

The policy applies to every Action in the run, not to the run as a whole. A Flow with three Actions and `timeout: 5_000` can take longer than five seconds.

A retry happens only when `Jido.Error.retryable?/1` returns true. Timeouts, raised exceptions, and most Action errors are retryable by default, so `max_attempts` can repeat an Action that already reached an external system. Validation and config errors are not retried. Mark a failure as final with `retry: false`. See [Flow Errors](flow-errors.md#retries).

```elixir
defmodule ExecutionGuide.ChargeCard do
  use Jido.Action, name: "execution_guide_charge_card"

  @impl true
  def run(_params, %{attempts: attempts}) do
    case Agent.get_and_update(attempts, &{&1 + 1, &1 + 1}) do
      3 -> {:ok, %{charged: true}}
      _attempt -> {:error, Jido.Error.execution_error("gateway busy", %{reason: :busy})}
    end
  end
end

{:ok, attempts} = Agent.start_link(fn -> 0 end)

{:ok, %{charged: true}} =
  Jido.Exec.run(ExecutionGuide.ChargeCard, %{}, %{attempts: attempts}, max_attempts: 3)

3 = Agent.get(attempts, & &1)
```

## Control concurrency

`:max_concurrency` falls back to `config :jido, max_concurrency: n`, then to the smaller of `System.schedulers_online/0` and 10. It must be a positive integer.

With a limit above 1, a Flow runs ready components concurrently. With a limit of 1, it runs them one at a time. The same limit covers nested and collection work in the run. Reduce and Iterate call their Action in sequence at any limit. A single Action target has nothing to run concurrently.

Result order does not depend on finish order. Map and Parallel results keep input and declaration order.

## Understand the process model

`Jido.Exec.run/4` starts an unlinked temporary task, then blocks until it finishes. The call has no caller-side timeout. Set `:timeout` when an Action can hang.

- The task keeps the caller's group leader, so `IO.puts/1` and captured output still work.
- An Action crash, even `:kill`, returns `{:error, error}`. It cannot exit the caller.
- If the caller exits, a watcher kills the task and the processes linked to it.

Pass `:task_supervisor` to run under your own `Task.Supervisor` and to apply its limits. The supervisor must be alive on the local node. Otherwise the call returns a config error before any work starts.

Your Action does not run in the calling process. A PID passed through context still works during immediate execution, but `self()` inside the Action is not the caller.

## Know what a Flow compiles to

`Jido.Exec.compile/2` turns any target into a `Runic.Workflow`. An Action becomes a one-node Workflow, and a Flow becomes a larger one. Runic plans runnable work and applies the policy. Jido validates params and output around each Action call.

`Jido.Exec.run/4` validates Flow input, compiles, and runs. A Flow that contains `await`, `timer`, or `selection` fails with a `:unsupported_host` config error because immediate execution cannot suspend.

The run emits `[:jido, :flow, ...]` events once for a Flow and `[:jido, :action, ...]` events for each Action attempt. `Jido.Telemetry.Exec.event_names/0` lists them. See [Debug Flows](debugging-flows.md#watch-a-run-with-telemetry).

## Next steps

- [Execute Flows](flow-execution.livemd) walks through running a Flow step by step.
- [Managed Execution](managed-execution.md) covers supervised runs with Runic.
- [Flow Errors](flow-errors.md) lists the failures you can handle.
