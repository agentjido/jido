# OTP Concepts

You can write Agents and Actions without knowing OTP. Once you run them as
live processes, you need to know what Jido starts, how it handles messages,
and what survives a crash. This guide maps each OTP concept to the place Jido
uses it.

| OTP concept | Where Jido uses it |
| --- | --- |
| Process and mailbox | One Agent Server process per live Agent. Signals arrive as messages and run one at a time. |
| `:gen_statem` | `Jido.AgentServer`. Its states are the phases of a Turn. |
| Call and cast | `call/3`, `cast/3`, `submit/3`, and `await/2`. |
| Supervisor | The Jido instance and each Agent activation. |
| Registry | Looks up a live Agent by its ID. |
| Task | Actions, commit hooks, and Directives run in tasks the Server owns. |
| Link and monitor | Owned work stops with the Server. Attached owners are monitored. |
| ETS | Runtime metadata and the last committed Agent for crash recovery. |

## One Process Per Agent

`Jido.start_agent/2` starts one Agent Server process for one Agent instance.
It holds the committed Agent, its revision, and private runtime data.

Each Signal becomes one Turn: route selection, execution, commit, and effects.
The Server runs one Turn at a time, so two Signals to the same Agent never
race on its state. Different Agents run in parallel.

Reads don't wait for a running Turn. `Jido.AgentServer.agent/2` and
`status/2` return the last committed value immediately. You never read a
partial Turn.

## Server Phases

`Jido.AgentServer` is a `:gen_statem`. `status/2` reports its current phase:

| Phase | Meaning |
| --- | --- |
| `:initializing`, `:restoring` | Starting, or loading saved state. |
| `:idle` | Ready for the next Signal. |
| `:preparing` | Plugins prepare input. The Server selects a route. |
| `:starting`, `:running` | The Action or Flow runs. |
| `:waiting` | A durable Flow waits for external input. |
| `:saving` | Writing the candidate to storage. |
| `:effects` | Commit hooks and Directives run. |
| `:policy` | The error policy runs after a failed Turn. |
| `:hibernating` | Saving before a stop. |

While a Turn runs, the Server postpones new Turns. `max_postponed_signals:`
caps that queue at 1,000 by default. Past the cap, the Server drops extra casts
and logs them.

## Calls And Casts

| Function | Returns |
| --- | --- |
| `Jido.AgentServer.call/3` | `{:ok, agent, directives}` after commit, or `{:error, reason}`. |
| `Jido.AgentServer.cast/3` | `:ok` once sent. No result. |
| `Jido.AgentServer.submit/3` | A pending handle. The Turn is queued. |
| `Jido.AgentServer.await/2` | The `call/3` result for a pending handle. |

`submit/3` and `await/2` wrap OTP's `send_request` and `wait_response`. Only
the process that submitted a handle can await it.

> #### A caller timeout doesn't cancel the Turn {: .warning}
>
> When `call/3` times out, your process stops waiting. The Turn keeps running
> and can still commit. Use `Jido.AgentServer.cancel/2` or `cancel_turn/3` to
> stop pre-commit work.

Calls and submits also take `admission_timeout:` (default 5,000 ms): the
longest a queued Turn waits before it starts. Casts have no admission
deadline.

## Supervisors

### The Jido Instance

`Jido.start/0` starts the default instance, `Jido.Default`. In an
application, define your own and add it to your supervision tree:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, namespace: "my-app/agents"
end

children = [MyApp.Jido]
```

The instance is a `:one_for_one` supervisor. Every Agent in it shares these
children:

| Child | Purpose |
| --- | --- |
| `Runic.Runner` | Runs Action and Flow work. |
| `Task.Supervisor` | Instance tasks. `max_tasks:` sets the limit. |
| Registration guard and Registry | Map live Agent IDs to processes. |
| Runtime store | Runtime metadata in ETS. |
| `DynamicSupervisor` | One activation per live Agent. |

### The Agent Activation

`Jido.start_agent/2` starts an activation, not a bare process:

```text
Jido instance (one_for_one)
  -> DynamicSupervisor
       -> Jido.AgentServer.Supervisor (one_for_all)   activation root
            -> Jido.AgentServer                         transient
            -> Plugin runtime supervisors               if declared
            -> declared child Agents                    if declared
```

The root is `:one_for_all`, so the Server and its required Plugin resources
restart together. The Server is `:transient`: a crash restarts it, a normal
stop doesn't.

After a crash, the Server resumes from the last committed Agent and revision.
The activation root keeps that copy in ETS. It survives a worker crash. It
doesn't survive losing the activation or restarting the BEAM. Use persistence
for that.

The Server links to its supervisor, not to the process that called
`start_agent/2`. The caller can exit and the Agent keeps running.

## Registry And IDs

A PID changes on restart. Look Agents up by ID instead:

```elixir
pid = Jido.whereis_agent("live-counter")
agents = Jido.list_agents()
:ok = Jido.stop_agent("live-counter")
```

An ID is unique within its instance and partition. Starting a second Agent
with a live ID returns an error and leaves the running Agent alone.

Registry lookups are local to one node. For a stable address that doesn't
depend on a PID, use an Agent Ref, covered in the Run Agent Servers guides.

## Tasks And Links

The Server doesn't run your Action code in its own process:

- Actions and Flows run in a Runic worker under the instance Runner.
- `after_commit/3` hooks and Directives run in linked tasks.
- Error policy callbacks run in a separate task.

The Server stays responsive during a Turn, and it can stop that work. A Turn
timeout or cancel kills owned work before the Server replies or admits the
next Turn.

Owned work stops with the Server. A process your Action spawns and leaves
running isn't owned. Close resources before the Action returns, or use a
Plugin runtime for long-lived work. See
[Supervised Resources](plugin-supervised-resources.livemd).

`Jido.AgentServer.attach/3` monitors an owner process. While an owner is
attached, the idle timeout doesn't stop the Agent. When the owner exits, the
Server detaches it.

## ETS

Jido keeps non-durable runtime data in ETS:

- the instance runtime store: configuration and runtime metadata;
- the activation root: the last committed Agent and revision; and
- the ETS persistence adapter: Agent records for tests and local work.

None of it survives a BEAM restart. Use a durable adapter, such as Ecto, for
state that must.

## Timeouts

Each boundary has its own timeout:

| Option | Default | Limits |
| --- | --- | --- |
| `timeout` on `call/3`, `await/2` | 5,000 ms | How long you wait for a reply. |
| `admission_timeout` | 5,000 ms | How long a queued Turn waits to start. |
| `turn_timeout` | 60,000 ms | All pre-commit work, including retries. |
| `directive_timeout` | 5,000 ms | The whole Directive batch. |
| `commit_timeout` | 5,000 ms | The whole `after_commit/3` batch. |
| `readiness_timeout` | 5,000 ms | Plugin runtime startup. |
| `persistence_timeout` | 5,000 ms | One storage operation. |

Server timeouts are fixed when the Agent starts. Pass them to
`Jido.start_agent/2`, such as `turn_timeout: 30_000`. To set a default for
every Agent in an instance, start the instance with
`agent_server: [turn_timeout: 30_000]`.

## Limits

Jido uses standard OTP. It adds no scheduler, distributed registry, or
cluster-wide ownership. One Agent ID has one live Server per instance and
partition, on one node. A durable adapter stores state, but it isn't a
cross-node writer lease.

## Next

- [Life of a Signal](signal-to-effects.md) – every stage of a Turn.
- [Pure or Live Execution](pure-or-live-execution.md) – when you need a
  process.
- [`gen_statem`](https://www.erlang.org/doc/apps/stdlib/gen_statem.html) and
  [`Supervisor`](https://hexdocs.pm/elixir/Supervisor.html) for the OTP
  details.
