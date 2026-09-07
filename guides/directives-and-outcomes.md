# Directives and Outcomes

A Directive is a typed request for runtime work after an Agent state commit.
An Outcome is the terminal record for one admitted Turn.

## Built-In Directives

| Directive | Operation |
| --- | --- |
| `Emit` | Dispatch one Signal through a target |
| `EmitToParent` | Send a Signal to the logical parent |
| `EmitToChild` | Send a Signal to a tracked child |
| `Spawn` | Start a supervised OTP child |
| `SpawnAgent` | Start and track a child Agent |
| `AdoptChild` | Attach an existing live child |
| `StopChild` | Stop and remove one tracked child |
| `Stop` | Stop the current Agent Server |
| `Error` | Send a structured error to Server policy |

Use constructors from `Jido.Agent.Directive`:

```elixir
emit = Jido.Agent.Directive.emit(signal, dispatch_target)
to_child = Jido.Agent.Directive.emit_to_child(:worker, signal)
spawn = Jido.Agent.Directive.spawn_agent(MyApp.Worker, :worker)
```

A Plugin can define more Directive types. It owns their validation, optional
state update, and dispatch.

## Validate Before Commit

Jido validates all built-in and Plugin Directives before commit. Plugin-owned
state updates also run before commit. Runtime dispatch starts only after the
complete candidate is valid and durable storage has accepted it.

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

## Do Not Use Directives As A Queue

An ordinary Directive list is not a durable queue. A process or VM can stop
after commit and before dispatch completes. For durable delivery, save explicit
pending work or use a durable Signal Bus subscription when that contract fits.

See [Plugin Contract And Lifecycle](plugin-contract-and-lifecycle.md),
[Start Child Agents](child-agents.livemd), and
[Recoverable Effects](recoverable-effects.md).
