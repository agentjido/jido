# Directives and Outcomes

A Directive is a typed request for runtime work after an Agent state commit.
An Outcome is the terminal record for one admitted Turn.

## Return Explicit Effects

Use the explicit Action result contract:

```elixir
{:ok, next_state, directives}
```

The same result survives a one-step Flow. A longer Flow collects all successful
executed steps, including the last step and unreferenced outputs. It returns
one batch with its final output. `jido_action` carries opaque values; Jido core
validates each value as an owned Directive before commit. `Jido.Agent.cmd/3` still
returns `{:ok, candidate, directives}` without dispatch.

Effects use canonical dependency order, with component name as the tie breaker.
A nested Flow contributes once at its parent position. Choice contributes only
the selected branch. Map and Reduce use item order; Iterate uses iteration order.
Dispatch keeps decision effects before normal expander effects, and a
continuation appends the next executable's effects. Worker completion order
does not change the batch. Supported step-wise Flows return the same batch
only at successful completion.

A failed Flow, timeout, cancellation, invalid Directive, or invalid candidate
state prevents dispatch of the deferred batch. Action I/O can already have
occurred and cannot be undone. Map `:collect_errors` handles errors as data;
a successful Flow retains requests from successful items only.

The third element is an optional proper list of Directives. No wrapper is
required for Flow composition. Omit the list when no Directive is needed.
Put metadata in the output state. Non-list third success elements fail at the
Action boundary. Use a Jido Action release that contains Flow effect support;
the existing published dependency requirement does not identify that release.

## Built-In Directives

| Directive | Operation |
| --- | --- |
| `Emit` | Dispatch one Signal through a target |
| `EmitToParent` | Send a Signal to the logical parent |
| `EmitToChild` | Send a Signal to a tracked child |
| `SpawnProcess` | Start an untracked supervised OTP process |
| `SpawnChild` | Start and track a child Agent |
| `AdoptChild` | Attach an existing live child |
| `StopChild` | Stop and remove one tracked child |
| `Stop` | Stop the current Agent Server |
| `Error` | Send a structured error to Server policy |

Use constructors from `Jido.Agent.Directive`:

```elixir
emit = Jido.Agent.Directive.emit(signal, dispatch_target)
to_child = Jido.Agent.Directive.emit_to_child(:worker, signal)
child = Jido.Agent.Directive.spawn_child(MyApp.Worker, :worker)
process = Jido.Agent.Directive.spawn_process({Task, fn -> do_work() end})
```

A Plugin can declare more Directive types through `directives/1`. Each Directive
module owns its validation. The Plugin can reduce its owned state before commit
and dispatch Directives after commit through `reduce/2` and `dispatch/4`.

## Validate Before Commit

Jido validates all built-in and Plugin Directives before commit. Plugin-owned
state contributions also run before commit. Runtime dispatch starts only after
the complete candidate is valid and the required checkpoint has succeeded.

A direct `Jido.Agent.cmd/3` call returns the list but does not dispatch it.

## Read An Outcome

`Jido.Agent.Turn.Outcome` records:

- the Turn and Agent IDs;
- source and effective Signals;
- terminal status and stage;
- state versions before and after the Turn;
- whether the Turn committed;
- Directive completion, failure, and skip counts;
- timing and an optional error.

Statuses are `:succeeded`, `:failed`, `:cancelled`, `:timed_out`, and
`:indeterminate`. The first recovery question is always `committed?`.

An optional Plugin `after_commit/3` failure uses stage `:after_commit`. The
commit remains. Remaining notifications and Directives are skipped; no
Directive is counted as failed until Directive handling itself starts.

## Do Not Use Directives As A Queue

An ordinary Directive list is not a durable queue. A process or VM can stop
after commit and before dispatch completes. Restore does not replay that batch
or infer a terminal Outcome from the committed revision. A Directive timeout
also does not prove that an external effect did not occur before the task
stopped.

For `EmitToParent` and `EmitToChild`, successful dispatch means an asynchronous
cast was queued. The target can stop or reject the Signal before any state
commit. Use a stable work ID and a receiver acknowledgement Signal after its
commit when the work result matters.

For durable delivery, save explicit pending work or use a durable Signal Bus
subscription when that contract fits.

See [Plugin Contract And Lifecycle](plugin-contract-and-lifecycle.md),
[Start Child Agents](child-agents.livemd), and
[Recoverable Effects](recoverable-effects.md).
