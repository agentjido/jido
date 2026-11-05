# Managed Execution

This guide shows how to run a Flow under a supervised `Runic.Runner` Worker, so you can observe it, step it by hand, stop it, resume it, and cancel it.

Use `Jido.Exec.start/6` when a run must outlive its caller or when you control its progress. Use `Jido.Exec.run/4` when you want the result now. To run a Flow inside an Agent Turn, see [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd).

The examples below use this Flow.

```elixir
defmodule ManagedGuide.ChargeInvoice do
  use Jido.Action, name: "managed_guide_charge_invoice"

  @impl true
  def run(%{invoice_id: invoice_id, cents: cents}, _context) do
    {:ok, %{invoice_id: invoice_id, charged: cents}, [{:send_receipt, invoice_id}]}
  end
end

defmodule ManagedGuide.MarkPaid do
  use Jido.Action, name: "managed_guide_mark_paid"

  @impl true
  def run(%{invoice_id: invoice_id}, %{ledger: ledger}) do
    send(Process.whereis(ledger), {:marked_paid, invoice_id})
    {:ok, %{invoice_id: invoice_id, status: "paid"}}
  end
end

defmodule ManagedGuide.PayInvoice do
  use Jido.Flow, name: "managed_guide_pay_invoice"

  flow do
    step "charge",
      action: ManagedGuide.ChargeInvoice,
      params: %{invoice_id: input(:invoice_id), cents: input(:cents)}

    step "mark_paid",
      action: ManagedGuide.MarkPaid,
      params: %{invoice_id: result("charge", :invoice_id)}

    output result("mark_paid")
  end
end

Process.register(self(), ManagedGuide.Ledger)
context = %{ledger: ManagedGuide.Ledger}
invoice = %{invoice_id: "inv-77", cents: 4_200}
```

## Start a Runner

Add a Runner to your supervision tree.

<!-- partial -->
```elixir
children = [
  {Runic.Runner, name: MyApp.Runner}
]
```

The examples start one directly.

```elixir
{:ok, _runner} = Runic.Runner.start_link(name: ManagedGuide.Runner)
```

With no `:store` option, the Runner keeps its checkpoints in ETS, which survive a Worker restart in the same VM but not a VM restart. See [choose a Store](#choose-a-store).

## Start a run and read its result

Give each run a stable ID. The ID can be any term. `Jido.Exec.start/6` returns the Worker PID once the input is admitted. It does not wait for the work.

Use the `on_idle` hook to learn that the Worker has no more work to do, then read the result with `Jido.Exec.result/2`.

```elixir
owner = self()
hooks = [on_idle: fn _worker_state -> send(owner, :idle) end]

{:ok, _worker} =
  Jido.Exec.start(ManagedGuide.Runner, "payment-1", ManagedGuide.PayInvoice, invoice, context, hooks: hooks)

receive do
  :idle -> :ok
after
  1_000 -> raise "the run did not finish"
end

{:ok, %{invoice_id: "inv-77", status: "paid"}, [{:send_receipt, "inv-77"}]} =
  Jido.Exec.result(ManagedGuide.Runner, "payment-1")
```

`Jido.Exec.result/2` returns the same shapes as `Jido.Exec.run/4`. While work is active it returns an `ExecutionError` with `details.reason: :execution_active`, so you can also call it repeatedly until the run settles. Starting a second run with an ID that has a live Worker returns an error with `details.reason: {:already_started, pid}` and leaves the existing Worker alone.

Do not call Runner functions from inside a hook. A hook runs in the Worker, so a synchronous call back to it blocks. Send a message to another process instead, as above.

## Pass portable data

Managed execution accepts only portable data. `Jido.Exec.start/6` rejects a PID, port, reference, or function anywhere in params, context, or Instruction metadata before it starts a Worker.

```elixir
{:error, %Jido.Error.ExecutionError{details: %{reason: :non_portable_durable_value, type: :pid}}} =
  Jido.Exec.start(ManagedGuide.Runner, "payment-2", ManagedGuide.PayInvoice, invoice, %{ledger: self()})
```

An Action result that holds such a value fails the same way when the Action returns. Pass a registered name in place of a PID, as this guide does with `ledger`.

Runic does not persist context. Pass it again when you resume.

## Set options

`Jido.Exec.start/6` takes the policy options from [Execution](execution.md#set-policy-options), except `:task_supervisor`, plus these Worker options. `Jido.Exec.resume/4` takes the same set. Options are not saved, so pass them again on resume.

| Option | Values | Meaning |
| --- | --- | --- |
| `:max_concurrency` | Positive integer | Concurrent units. Same default as `Jido.Exec.run/4` |
| `:dispatch_mode` | `:automatic` (default), `:manual` | Who dispatches ready work |
| `:checkpoint_strategy` | `:every_cycle`, `:on_complete`, `:manual`, `{:every_n, n}` | When the Worker saves |
| `:hooks` | Keyword list | `on_dispatch/2`, `on_complete/3`, `on_failed/3`, `on_idle/1`, and other Worker hooks |
| `:on_complete` | Function | Runic Worker completion callback |
| `:executor`, `:executor_opts` | Module, keyword list | How runnables execute |
| `:scheduler`, `:scheduler_opts` | Module, keyword list | How runnables group into units |
| `:promise_opts` | Keyword list | Shorthand for the chain-batching scheduler |

## Step a run by hand

Start with `dispatch_mode: :manual`, then call `Jido.Exec.step/2`. Each `{:ok, workflow}` means Runic dispatched one unit, which may still be running. `{:complete, workflow}` means nothing is ready, or that admission has stopped. In both cases `workflow` is the current `Runic.Workflow`.

Wait for each unit before the next step, or retry when `Jido.Exec.step/2` returns `{:error, :busy}`.

```elixir
unit_hooks = [
  on_complete: fn _runnable, _duration, _state -> send(owner, :unit_done) end,
  on_failed: fn _runnable, _reason, _state -> send(owner, :unit_done) end
]

{:ok, _worker} =
  Jido.Exec.start(ManagedGuide.Runner, "payment-3", ManagedGuide.PayInvoice, invoice, context,
    dispatch_mode: :manual,
    max_concurrency: 1,
    hooks: unit_hooks
  )

{:error, %Jido.Error.ExecutionError{details: %{reason: :execution_active}}} =
  Jido.Exec.result(ManagedGuide.Runner, "payment-3")

step_all = fn step_all ->
  case Jido.Exec.step(ManagedGuide.Runner, "payment-3") do
    {:ok, %Runic.Workflow{}} ->
      receive do
        :unit_done -> step_all.(step_all)
      after
        1_000 -> raise "the unit did not finish"
      end

    {:complete, %Runic.Workflow{} = workflow} ->
      workflow
  end
end

%Runic.Workflow{} = step_all.(step_all)

{:ok, %{status: "paid"}, _effects} = Jido.Exec.result(ManagedGuide.Runner, "payment-3")
```

Manual mode belongs to the Worker process. It is not a saved pause and it is not an approval record. For a saved pause, use [Flow Waits](flow-waits.md). `Runic.Runner.continue/2` switches a Worker to automatic dispatch.

## Stop and resume

`Runic.Runner.stop/3` saves the Worker and stops it. `Jido.Exec.resume/4` loads the run from the Store and starts a new Worker. Completed Actions do not run again. Pending work runs in new tasks.

```elixir
:ok = Runic.Runner.stop(ManagedGuide.Runner, "payment-1", persist: true)

{:ok, _worker} = Jido.Exec.resume(ManagedGuide.Runner, "payment-1", context, hooks: hooks)

{:ok, %{status: "paid"}, _effects} = Jido.Exec.result(ManagedGuide.Runner, "payment-1")
```

`Jido.Exec.resume/4` picks a recovery mode for you. With a Store that saves facts it uses `:hybrid`, otherwise `:full`. A native Batch workflow, which Map compiles to, falls back to `:full`. Pass `rehydration: :full`, `:hybrid`, or `:lazy` to choose. `:hybrid` and `:lazy` need fact storage and return a config error without it.

An Action that was running when its Worker stopped starts again from the beginning on resume. Make such Actions idempotent. The result above is available at once because the run had finished. For a run with pending work, wait for `on_idle` or retry while `Jido.Exec.result/2` returns `:execution_active`.

## Handle a failed run

A failed Action stops admission: units already running can finish, but none start. `Jido.Exec.result/2` returns the failure.

```elixir
defmodule ManagedGuide.DeclineCard do
  use Jido.Action, name: "managed_guide_decline_card"

  @impl true
  def run(_params, _context) do
    {:error, Jido.Error.execution_error("card declined", %{reason: :card_declined, retry: false})}
  end
end

{:ok, _worker} =
  Jido.Exec.start(ManagedGuide.Runner, "payment-4", ManagedGuide.DeclineCard, %{}, %{}, hooks: hooks)

receive do
  :idle -> :ok
after
  1_000 -> raise "the run did not settle"
end

{:error, %Jido.Error.ExecutionError{details: %{reason: :card_declined}}} =
  Jido.Exec.result(ManagedGuide.Runner, "payment-4")

{:ok, %{status: :stopped, active_units: 0, causes: [%{kind: :failed}]}} =
  Runic.Runner.admission_status(ManagedGuide.Runner, "payment-4")
```

`Runic.Runner.admission_status/2` returns `status`, `active_units`, and `causes`. A cause with `kind: :uncertain` means the executor ended with no result, so you cannot tell whether the Action ran.

`Runic.Runner.continue/2` opens a new admission scope once active units have drained. If a unit is uncertain, it runs again, along with any external effects it has.

## Cancel a run

`Runic.Runner.cancel/2` stops the Worker without saving and waits for its tasks to stop. It does not undo external effects.

```elixir
defmodule ManagedGuide.WaitForBank do
  use Jido.Action, name: "managed_guide_wait_for_bank"

  @impl true
  def run(_params, %{ledger: ledger}) do
    send(Process.whereis(ledger), {:bank_call_started, self()})
    Process.sleep(:infinity)
  end
end

{:ok, _worker} = Jido.Exec.start(ManagedGuide.Runner, "payment-5", ManagedGuide.WaitForBank, %{}, context)

task =
  receive do
    {:bank_call_started, pid} -> pid
  after
    1_000 -> raise "the Action did not start"
  end

{:ok, %{active_units: 1, status: :open}} = Runic.Runner.admission_status(ManagedGuide.Runner, "payment-5")

:ok = Runic.Runner.cancel(ManagedGuide.Runner, "payment-5")

false = Process.alive?(task)
{:error, :not_found} = Runic.Runner.admission_status(ManagedGuide.Runner, "payment-5")
```

## Choose a Store

| Store | Survives Worker restart | Survives VM restart |
| --- | --- | --- |
| `Runic.Runner.Store.ETS` (default) | Yes | No |
| `Runic.Runner.Store.Mnesia` with `disc_copies: true` | Yes | Yes |
| Your own `Runic.Runner.Store` adapter | Depends on the adapter | Depends on the adapter |

Start an explicit Store yourself, before the Runner. The Runner assumes you own its lifecycle.

<!-- partial -->
```elixir
children = [
  {Runic.Runner.Store.Mnesia, runner_name: MyApp.Runner, disc_copies: true},
  {Runic.Runner, name: MyApp.Runner, store: Runic.Runner.Store.Mnesia, store_opts: [disc_copies: true]}
]
```

Computation and persistence finish separately. A run can have a result while its save is pending or failed. To get a save you can rely on, call `Runic.Runner.checkpoint/2`, which returns `:ok` after the Store acknowledges. `Runic.Runner.persistence_status/2` reports `:saved`, `:pending`, or the failure.

Nothing resumes stored runs for you after a VM restart. Your application records the run IDs and calls `Jido.Exec.resume/4` for each.

`Jido.Exec.start/6` rejects a Flow that contains waits, because a Runner has no way to deliver wait input. Run such a Flow in an Agent. See [Flow Waits](flow-waits.md).

## Next steps

- [Flow Waits](flow-waits.md) suspends a Flow until an event or timer.
- [Debug Flows](debugging-flows.md) inspects a live run.
- [Flow Security](flow-security.md) covers what a Store sees.
