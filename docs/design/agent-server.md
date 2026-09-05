> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Agent Server

[Design overview](README.md) | Previous: [Plugins](plugins.md) | Next: [Jido instance](jido-instance.md)

- Depends on: Agent, Turn Evaluator, OTP, persistence, and Plugin runtimes.
- Defines: the internal live Agent process, serialized phases, control
  boundaries, and failure behavior.

## Boundary

`Jido.AgentServer` is the internal OTP owner for one live Agent. It uses
`:gen_statem` and starts one evaluation task for each admitted Signal.
Directive work runs in separate supervised tasks. Application code and
external packages use the Ref-first `MyApp.Jido` instance facade. They do not
call Agent Server functions or send messages to its PID.

The Agent Server module can expose standard OTP start functions for the Jido
Agent Pool. These are internal supervision contracts, not a public application
API or a semantic-version extension boundary.

The Server owns:

- One committed `%Jido.Agent{}` and Agent state version.
- One serialized Signal mailbox.
- At most one active Turn.
- The active Turn ID, control stage, caller, task, monitor, and timer.
- Persistence, commit, restore, and transient Directive dispatch.
- Plugin runtime references returned by `PluginRuntimePool`.
- Admission limits, idle hibernation state, and owner attachments.

The Server does not add domain behavior. `Jido.Agent` remains the domain value,
and `Jido.Agent.cmd/3` remains the direct evaluation boundary.

## Private runtime state

Server state is private framework data:

```elixir
%Jido.AgentServer.State{
  agent: %Jido.Agent{},
  initial_agent: %Jido.Agent{},
  state_version: 7,
  active: nil | %{
    turn_id: "019...",
    stage: :evaluate | :commit | :directive,
    evaluation_task: nil | %{pid: task_pid, ref: monitor_ref},
    turn_timer: nil | timer_ref,
    caller: caller,
    start_version: 7
  },
  plugin_runtimes: %{plugin_id => runtime_ref},
  persistence: nil | persistence_context,
  postponed_tokens: MapSet.new(),
  attachments: MapSet.new(),
  directive_task: nil | task_ref
}
```

The initial Agent is the explicit nonpersistent restart source. A persistent
child specification retains only the Agent Ref and Jido instance as its
restart source. Runtime PIDs, tasks, monitors, and timers never enter the Agent
or checkpoint.

## Runtime phases

The Server has four phases:

| Phase | Work | New Signals |
| --- | --- | --- |
| `:initializing` | Validate creation or restore state, prepare Plugin runtimes, wait for readiness, and complete the initial durable boundary. | Postpone. |
| `:idle` | No active Turn exists. Background Plugin work can remain pending. | Admit the next Signal. |
| `:running` | Evaluate one Signal or commit its candidate. | Postpone within the limit. |
| `:directing` | Dispatch the current Turn Directive batch in order. | Postpone within the limit. |

For persistent creation, provisional Plugin runtimes become ready before Jido
writes the initial active Record. For activation, Jido first restores the
Record and starts runtimes from committed Plugin state. Explicit recovery
workers can resume pending work while the Agent accepts Signals.

If a provisional runtime exits before the initial write, creation readiness
fails. Jido stops all provisional roots and writes no Record. It does not write
the Record while a required runtime is unavailable.

Live Directive dispatch remains within the current Turn. A Plugin can wake
a background worker and return without waiting for its business result. The
worker records completion through another Signal. Pending work in Plugin state
does not by itself block later Turns.

## Turn control stages

One active Turn has three ordered control stages:

| Stage | Work | Cancellable | Work timeout |
| --- | --- | --- | --- |
| `:evaluate` | Route resolution, Plugin preparation, executable evaluation, Plugin contribution, and candidate validation. | Yes. | Per-Agent `turn_timeout`; default `:infinity`. |
| `:commit` | Build the Commit, run persistence when configured, and replace live state. | No. | Instance `persistence_timeout` for persistent work. |
| `:directive` | Dispatch each Directive in the current Turn. | No. | Per-Agent `directive_timeout` for each entry. |

The evaluation timer starts when the evaluation task starts. Mailbox wait time
is not part of it. On timeout or accepted cancellation, the Server terminates
the task, waits for its monitored `:DOWN`, rejects late results, and keeps the
committed Agent unchanged.

The commit boundary starts when the Server accepts a validated candidate and
sets the stage to `:commit`. For a persistent Agent, this happens before the
first persistence call. For a nonpersistent Agent, it happens before the live
state swap. Cancellation is too late from this point.

A persistence timeout is an indeterminate write error. The Server keeps its
prior live state, starts no new Directive, and stops with
`:lost_write_authority`. A later explicit activation loads the authoritative
Record.

A Directive timeout records a post-commit failure and follows the runtime
error policy. It does not create a durable replay obligation. A delivery
capability retains its explicit pending intent and applies its own retry policy.

If cancellation and a task result race, the first event processed by
`:gen_statem` sets the boundary. A later event cannot change the decision.

## Ref-first instance API

The generated Jido instance facade is the only public live Agent API:

```elixir
MyApp.Jido.start_agent(agent_module_or_agent, opts \\ [])
MyApp.Jido.activate_agent(agent_ref, opts \\ [])
MyApp.Jido.call(agent_ref, signal, opts \\ [])
MyApp.Jido.cast(agent_ref, signal, opts \\ [])
MyApp.Jido.send_request(agent_ref, signal, opts \\ [])
MyApp.Jido.receive_response(request_id, timeout \\ 5_000)
MyApp.Jido.cancel(agent_ref, opts \\ [])
MyApp.Jido.cancel_turn(agent_ref, turn_id, opts \\ [])
MyApp.Jido.stop_agent(agent_ref, opts \\ [])
MyApp.Jido.hibernate(agent_ref, opts \\ [])
MyApp.Jido.thaw(agent_ref, opts \\ [])
MyApp.Jido.delete_agent(agent_ref, opts \\ [])
```

The facade resolves an Agent Ref to its current local Server. `whereis_local/2`
can return a PID for local observation, but the PID has no supported public
Agent Server command API.

`start_agent/2` constructs or validates a complete module-owned Agent. It waits
for Plugin readiness and the initial persistence boundary before it returns.
`activate_agent/2` restores an existing active Record and starts Plugin runtimes.
It does not wait for all background recovery work to finish.

## Agent runtime options

`start_agent/2` accepts these runtime options in addition to Agent instance
options:

| Option | Meaning |
| --- | --- |
| `:partition` | Optional Agent Ref and persistence partition. |
| `:max_postponed_signals` | Postponed admission limit. Default `1_000`. |
| `:max_directives_per_turn` | Directive batch limit. Default `:infinity`. |
| `:turn_timeout` | Pre-commit evaluation timeout. Default `:infinity`. |
| `:readiness_timeout` | Timeout for each Plugin runtime readiness check. Default `5_000`. |
| `:directive_timeout` | Timeout for each post-commit Directive. Default `5_000`. |
| `:default_dispatch` | Default target for emitted Signals. |
| `:error_policy` | `:continue` or `:stop` after a normal pre-commit error. Default `:continue`. |
| `:idle_timeout` | Idle hibernation timeout. Default `:infinity`. |

The Jido instance validates these keyword options with a private Zoi schema.
`turn_timeout` and `idle_timeout` accept `:infinity` or a positive number of
milliseconds. `readiness_timeout`, `directive_timeout`, and instance
`persistence_timeout` are positive numbers of milliseconds.

The error policy is closed data, not a callback. `:continue` returns to idle
after it reports a normal pre-commit error. `:stop` stops the Agent after it
reports that error. Persistence failures, broken framework invariants, and
Directive failures have fixed stop behavior. An error policy cannot mark an
durable work complete, change write authority, emit a Signal, or run
application code. Policy `:stop` uses a controlled shutdown and does not cause
the transient child to restart.

## Signal and control results

`call/3` returns the live `Result`:

```elixir
{:ok, committed_agent}
{:error, jido_error}
```

A successful Result proves that Agent and Plugin state committed. It does not
prove that post-commit Directives completed.

`cast/3` is a best-effort send. `:ok` means that Jido sent the message to the
resolved local Server. It does not confirm admission, evaluation, or commit.
The Server can drop a cast after it reaches the postponed admission limit and
reports the rejection through telemetry.

`send_request/3` starts an OTP asynchronous request. `receive_response/2`
keeps the standard OTP envelope:

```elixir
{:reply, {:ok, committed_agent}}
{:reply, {:error, jido_error}}
:timeout
{:error, {reason, server}}
```

The `call/3` and `send_request/3` request timeout is also an admission deadline
while the Signal is postponed. `receive_response/2` has only a caller wait
timeout. These values are separate from `turn_timeout`. A caller timeout after
evaluation starts does not cancel the Turn.

`cancel/2` cancels the active `:evaluate` stage. `cancel_turn/3` also requires
the stable Turn ID to match. An accepted cancellation returns `:ok`; the active
Signal request receives a RuntimeError with code `:turn_cancelled`. Rejection
uses `:no_active_turn`, `:turn_mismatch`, or `:too_late`.

Task code for one active Turn must not make a synchronous Signal call to the
same Agent Ref. Jido detects this reentry and returns a defined error. A
Directive or asynchronous cast can send a later Signal through the mailbox.

## Failure boundaries

| Failure | Required behavior |
| --- | --- |
| Invalid Signal, route, callback return, or candidate | Return a defined error and keep committed state. |
| Action, Flow, or Plugin callback fails | Abort evaluation and keep committed state. |
| Evaluation exceeds `turn_timeout` | Terminate the task, return a timeout error, and keep committed state. |
| Any persistence write error or timeout | Keep prior live state, start no new Directive, and stop with lost write authority. |
| Evaluation or Server invariant breaks | Crash and use the configured restart source. |
| Plugin runtime exits | Replace it from a fresh Init with current committed Plugin state and version. |
| Directive dispatch fails or times out | Record a post-commit failure and apply error policy without rollback. Explicit delivery intent remains in Plugin state. |

Only a confirmed persistence success lets the current Server keep write
authority. No error policy can change these failure boundaries.

## Public inspection values

The instance facade provides read operations:

```elixir
MyApp.Jido.agent(agent_ref, opts \\ [])
MyApp.Jido.plugin_state(agent_ref, plugin_id, opts \\ [])
MyApp.Jido.status(agent_ref, opts \\ [])
MyApp.Jido.commit(agent_ref, opts \\ [])
MyApp.Jido.plugin_runtimes(agent_ref, opts \\ [])
```

`agent/2` returns only the current committed Agent. `commit/2` returns the
current `%Jido.Agent.Commit{}`. It does not create a duplicate Snapshot type.

`status/2` returns one defined runtime view:

```elixir
%Jido.Agent.Status{
  phase: :initializing | :idle | :running | :directing,
  agent_ref: agent_ref,
  restart_mode: :restore | :reset_to_initial,
  state_version: 7,
  active: nil | %Jido.Agent.Turn.Status{
    turn_id: "019...",
    stage: :evaluate | :commit | :directive,
    source_signal_id: "019...",
    source_signal_type: "counter.increment",
    effective_signal_id: nil | "019...",
    effective_signal_type: nil | "counter.increment",
    start_version: 7,
    committed_version: nil | 8,
    directive_index: nil | 0,
    directive_count: 0,
    started_at: 1_788_000_000_000
  },
  postponed: 0,
  postponed_limit: 1_000,
  message_queue_len: 0,
  plugin_runtime_count: 0,
  attached: 0,
  turn_timeout: :infinity,
  readiness_timeout: 5_000,
  directive_timeout: 5_000,
  idle_timeout: :infinity,
  idle_timer?: false
}
```

`Jido.Agent.Status` and `Jido.Agent.Turn.Status` are Zoi-backed public values.
They contain only bounded live observation. Status validation enforces these
rules:

- `:initializing` and `:idle` have no active Turn.
- `:running` has an active Turn at `:evaluate` or `:commit`.
- `:directing` has an active committed Turn at `:directive`.
- `:idle` requires no active Turn. Explicit Plugin work can remain pending.
- Restore mode requires configured persistence.
- Reset mode requires a nonpersistent Server.
- Effective Signal fields can be nil only during evaluation.
- Directive position fields apply only during the Directive stage.

## Turn Outcome

The Server emits one terminal `%Jido.Agent.Turn.Outcome{}` through telemetry
when all live work for a Turn stops:

```elixir
%Jido.Agent.Turn.Outcome{
  agent_ref: agent_ref,
  turn_id: "019...",
  source_signal_id: "019...",
  signal_id: "019...",
  signal_type: "counter.increment",
  status: :succeeded | :failed | :cancelled | :timed_out | :indeterminate,
  stage: :evaluate | :commit | :directive,
  committed?: true,
  state_version_before: 7,
  state_version_after: 8,
  error: nil | Jido.Error.t(),
  directive_count: 2,
  directives_completed: 2,
  failed_directive_id: nil,
  started_at: 1_788_000_000_000,
  finished_at: 1_788_000_000_012,
  duration_ms: 12
}
```

Outcome validation ties status to the commit boundary. A pre-commit failure has
`committed?: false`, no state version after, and no Directive work. A
post-commit failure has `committed?: true`, keeps the committed version, and
identifies its failed entry. The Outcome contains identities and counts, not
Agent state, Plugin state, Signals, or Directive payloads.

There is no outbound Agent callback and no per-Server debug timeline. Domain
output is the committed Agent. External work is a Directive. Runtime
observation is telemetry and public bounded status data.
