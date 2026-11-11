# Direct Runic Execution

`Jido.Exec.run/4` is the normal way to run an Action or Flow. Use direct
`Runic.Runner` execution when you need to inspect a workflow or move it one
scheduler unit at a time.

This is an advanced escape hatch. It exposes Runic lifecycle and persistence
rules. Use `Jido.Durable` when an application needs a durable business run,
Signal input, waits, or host scheduling.

## Compile the Flow

Resolve the input once, then compile the Instruction. An Action becomes a
one-node Runic workflow. A Flow becomes its full Runic graph.

```elixir
params = %{invoice_id: "inv-77", cents: 4_200}
context = %{ledger: MyApp.Ledger}

{:ok, instruction} = Jido.Instruction.resolve(MyApp.PayInvoice, params, context)
{:ok, workflow} = Jido.Exec.compile(instruction, [])
```

Runic receives the canonical Flow input directly. Use `Jido.Exec.Fact` only
when the input contains process-local values that Runic cannot identify as
portable data.

```elixir
input =
  instruction.params
  |> Jido.Exec.Fact.local_value()
```

The same input rule applies to an Action because Exec lowers it to a one-step
Flow.

## Start a Runner

Add a Runner to your supervision tree.

<!-- partial -->
```elixir
children = [
  {Runic.Runner, name: MyApp.Runner}
]
```

The default ETS Store survives a Worker restart in the same VM. It does not
survive a VM restart.

## Start one observed execution

Start the workflow, then admit one input occurrence. Keep the returned Runic
execution identity. `Jido.Exec.result/2` uses it to select the correct result.

```elixir
run_id = "payment-1"

{:ok, _worker} =
  Runic.Runner.start_workflow(MyApp.Runner, run_id, workflow)

{:ok, execution_id} =
  Runic.Runner.start_execution(MyApp.Runner, run_id, input,
    run_context: %{_global: instruction.context}
  )
```

Wait for the execution to become quiescent, then project its result through
Jido.

```elixir
{:ok, observation} =
  Runic.Runner.await_execution(MyApp.Runner, run_id, execution_id, 5_000)

{:ok, current} = Runic.Runner.get_workflow(MyApp.Runner, run_id)
{:ok, output} = Jido.Exec.result(current, observation)
```

Runic observations are process-local. `Jido.Exec.result/2` does not project a
restored workflow without an observation. Use `Jido.Durable` when Jido must
restore and project the result after a process or VM restart.

## Step through a run

Start the Worker in manual dispatch mode. A direct `Runic.Runner.step/2` call
dispatches one scheduler unit.

```elixir
owner = self()

hooks = [
  on_complete: fn _runnable, _duration, _state -> send(owner, :unit_done) end,
  on_failed: fn _runnable, _error, _state -> send(owner, :unit_done) end
]

{:ok, _worker} =
  Runic.Runner.start_workflow(MyApp.Runner, "payment-debug", workflow,
    dispatch_mode: :manual,
    max_concurrency: 1,
    hooks: hooks
  )

{:ok, debug_execution_id} =
  Runic.Runner.start_execution(MyApp.Runner, "payment-debug", input,
    run_context: %{_global: instruction.context}
  )
```

Call `step/2` again after the dispatched unit finishes.

```elixir
step_all = fn step_all ->
  case Runic.Runner.step(MyApp.Runner, "payment-debug") do
    :ok ->
      receive do
        :unit_done -> step_all.(step_all)
      after
        1_000 -> raise "the unit did not finish"
      end

    {:error, :busy} ->
      step_all.(step_all)

    {:error, :not_runnable} ->
      Runic.Runner.get_workflow(MyApp.Runner, "payment-debug")

    {:error, :admission_stopped} ->
      Runic.Runner.get_workflow(MyApp.Runner, "payment-debug")
  end
end

{:ok, debug_workflow} = step_all.(step_all)
{:ok, debug_observation} =
  Runic.Runner.execution(MyApp.Runner, "payment-debug", debug_execution_id)

{:ok, output} = Jido.Exec.result(debug_workflow, debug_observation)
```

Manual dispatch is a debugging control. It is not a saved approval or wait.
Use a Jido Flow wait for a saved pause.

## Inspect, stop, resume, or cancel

The rest of the lifecycle stays in Runic.

```elixir
{:ok, workflow} = Runic.Runner.get_workflow(MyApp.Runner, run_id)
{:ok, admission} = Runic.Runner.admission_status(MyApp.Runner, run_id)
{:ok, persistence} = Runic.Runner.persistence_status(MyApp.Runner, run_id)

:ok = Runic.Runner.checkpoint(MyApp.Runner, run_id)
:ok = Runic.Runner.stop(MyApp.Runner, run_id, persist: true)

{:ok, _worker} =
  Runic.Runner.resume(MyApp.Runner, run_id,
    rehydration: :full,
    run_context: %{_global: instruction.context}
  )

:ok = Runic.Runner.cancel(MyApp.Runner, run_id)
```

Pass runtime context, scheduler policy, hooks, and Worker options again when
you resume. Runic does not store them in the workflow graph. An Action that was
active when the Worker stopped can run again. Such Actions must be idempotent.

## Choose a Store

| Store | Worker restart | VM restart |
| --- | --- | --- |
| `Runic.Runner.Store.ETS` | Survives | Does not survive |
| `Runic.Runner.Store.Mnesia` with disk copies | Survives | Survives |
| A custom `Runic.Runner.Store` adapter | Adapter-specific | Adapter-specific |

Start an explicit Store before the Runner. The Runner does not own an external
Store process.

Nothing resumes stored Runic runs after a VM restart. Your host must record the
run IDs and call `Runic.Runner.resume/3`, or use `Jido.Durable` for the Jido
durability contract.

## Next steps

- [Flow Waits](flow-waits.md) explains saved Signal and timer waits.
- [Debug Flows](debugging-flows.md) explains workflow inspection.
- [Flow Security](flow-security.md) explains what a Store can contain.
