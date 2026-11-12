# Agent Lifecycle

This guide explains the processes behind a live Agent, what happens when one fails, and why an Agent stops. It ends with the full list of startup options.

## The process tree

A Jido instance is a supervisor. Each Agent you start runs in its own activation under that instance.

```text
MyApp.Jido                     instance supervisor
|- Runner, Task supervisor, Registry, registration guard, runtime store
`- Agent supervisor            DynamicSupervisor
   `- activation               Supervisor, one per Agent
      |- AgentServer worker    runs Turns, answers reads
      |- owned child Agents    their own activations, under a DynamicSupervisor
      `- Plugin runtimes and topology buses
```

The worker is the PID you get from `Jido.start_agent/3`. The activation owns everything tied to the Agent's lifetime. `Jido.AgentServer.activation/1` returns its PID.

The children of an activation restart together. A worker restart therefore also restarts its Plugin runtimes and stops its owned children.

## Startup and readiness

`Jido.start_agent/3` returns when the worker is registered. Two steps can still be in progress: restoring saved state, and starting Plugin runtimes and topology members. During them, the `phase` in `Jido.AgentServer.status/2` is `:initializing`, Turns are rejected with `:not_ready`, and `Jido.whereis_agent/3` returns `nil`.

Call `Jido.AgentServer.await_ready/2` before you send work. It returns `:ok` when the server is ready. If startup fails, the worker stops with `{:shutdown, reason}`, and `await_ready/2` returns `{:error, reason}`. A caller timeout does not stop startup.

`:readiness_timeout` bounds Plugin startup, and `:persistence_timeout` bounds the restore. Each has a default of 5,000 ms. On expiry, the worker stops with `{:shutdown, :readiness_timeout}` or `{:shutdown, :persistence_timeout}`.

## Recover from a crash

When a worker exits abnormally, its activation starts a new one. The new worker loads the last committed Agent and revision, so a crash cannot lose a commit. An Agent with no persistence loads them from a checkpoint held by the activation. An Agent with persistence loads them from its store.

```elixir
defmodule LifecycleGuide.Counter do
  use Jido.Agent, name: "shelf_counter"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/shelves"

    route "shelf.add", as: :add do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end

    route "shelf.refuse", as: :refuse do
      action _input, schema: Jido.Joi.object(%{}), context: _context do
        {:error, Jido.Error.execution_error("shelf is locked")}
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: LifecycleGuide.Jido)
{:ok, counter} = Jido.start_agent(LifecycleGuide.Jido, LifecycleGuide.Counter, id: "shelf-1")
{:ok, %{state: %{count: 1}}, []} = Jido.AgentServer.call(counter, LifecycleGuide.Counter.add_signal!(%{}))

activation = Jido.AgentServer.activation(counter)
monitor = Process.monitor(counter)
Process.exit(counter, :kill)

receive do
  {:DOWN, ^monitor, :process, ^counter, :killed} -> :ok
after
  1_000 -> raise "the worker did not exit"
end

replacement =
  Enum.find_value(1..100, fn _attempt ->
    Process.sleep(10)

    case Jido.whereis_agent(LifecycleGuide.Jido, "shelf-1") do
      pid when is_pid(pid) and pid != counter -> pid
      _not_ready -> nil
    end
  end)

%{agent: %{state: %{count: 1}}, state_version: 1} = Jido.AgentServer.snapshot(replacement)
^activation = Jido.AgentServer.activation(replacement)
```

A worker restart has these effects:

- The Turn in progress is lost, and Jido stops its execution before the new worker takes any work. A durable Flow Turn resumes instead. See [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd).
- Queued casts are lost. Callers waiting on the old process exit, and `Jido.AgentServer.await/2` returns an error. Send those requests again.
- Owned children stop, and their tags are released. Independent children keep running and stay attached.
- Attached owners and closed admission carry over.
- `last_outcome`, `error_count`, and Turn history start empty.

An activation allows 3 restarts in 5 seconds. Past that limit, it exits with `:shutdown`. An Agent started with `Jido.start_agent/3` is then gone until you start it again.

A worker that exits with `:normal`, `:shutdown`, or `{:shutdown, reason}` is not restarted, and its activation stops with it.

## Handle failed Turns

A Turn that returns an error leaves the state unchanged. `:error_policy` decides what the server does next. The policy runs for Turns with the status `:failed`, not for cancelled or timed-out Turns. It also runs when an effect reports an error with `Jido.AgentServer.Directive.error_report/2`.

| `:error_policy` value | After a failed Turn |
| --- | --- |
| `:log_only` (default) | The server continues. |
| `:stop_on_error` | The worker stops with `{:shutdown, :agent_error}`. |
| `{:max_errors, n}` | The worker stops with `{:shutdown, :max_agent_errors}` when `error_count` reaches `n`. |
| `{:emit_signal, dispatch}` | The server dispatches a `jido.agent_server.error` Signal holding the outcome summary, then continues. A failed dispatch stops the worker with `{:shutdown, :error_signal_failed}`. |
| A two-argument function | It receives the error and the outcome summary. It returns `:continue` or `{:stop, reason}` with an atom reason. |

`error_count` rises with each failure and returns to 0 at the next commit, so `{:max_errors, n}` counts failures in a row.

```elixir
{:ok, strict} =
  Jido.start_agent(LifecycleGuide.Jido, LifecycleGuide.Counter, id: "shelf-2", error_policy: {:max_errors, 2})

refuse = LifecycleGuide.Counter.refuse_signal!(%{})
add = LifecycleGuide.Counter.add_signal!(%{})

{:error, %Jido.Error.ExecutionError{}} = Jido.AgentServer.call(strict, refuse)
1 = Jido.AgentServer.status(strict).error_count

{:ok, _agent, []} = Jido.AgentServer.call(strict, add)
0 = Jido.AgentServer.status(strict).error_count

monitor = Process.monitor(strict)
{:error, _reason} = Jido.AgentServer.call(strict, refuse)
{:error, _reason} = Jido.AgentServer.call(strict, refuse)

receive do
  {:DOWN, ^monitor, :process, ^strict, {:shutdown, :max_agent_errors}} -> :stopped
after
  1_000 -> raise "the policy did not stop the worker"
end
```

The caller still gets its `{:error, reason}` before the worker stops. A function policy can do its own work, such as alerting, within `:error_policy_timeout`.

```elixir
observer = self()

policy = fn error, outcome ->
  send(observer, {:turn_failed, error.message, outcome.status, outcome.committed?})
  :continue
end

{:ok, watched} =
  Jido.start_agent(LifecycleGuide.Jido, LifecycleGuide.Counter, id: "shelf-3", error_policy: policy)

{:error, _reason} = Jido.AgentServer.call(watched, refuse)

receive do
  {:turn_failed, "shelf is locked", :failed, false} -> :observed
after
  1_000 -> raise "the policy did not run"
end
```

## Stop an Agent

| Function | Effect |
| --- | --- |
| `Jido.stop_agent/3` | Stops an Agent in the named instance by PID or ID. It returns `{:error, :not_found}` when the Agent is absent or belongs to another instance. |
| `Jido.stop_agent_ref/4` | The same, through a `Jido.Agent.Ref`. |
| `Jido.AgentServer.stop/3` | Stops any server. The default reason is `:shutdown` and the default wait is 5,000 ms. A reason other than `:normal`, `:shutdown`, or `{:shutdown, term}` becomes `{:shutdown, reason}`. |
| `Jido.Agent.Directive.server_stop/1` | Stops the server from a Turn, after commit. |
| `Jido.AgentServer.hibernate/2` | Saves, then stops. See [Hibernate and Thaw](hibernate-thaw-and-activate.md). |
| `Jido.stop/1` | Stops the instance and all its Agents. |

`stop` returns after the activation has exited. A wait that expires exits the caller, and an Action in a Turn gets `{:error, :reentrant_turn}` from `stop`. Stopping does not wait for the active Turn. To let it finish first, call `Jido.AgentServer.quiesce/2`.

## Why a worker stopped

Monitor the worker to read its exit reason. All of these reasons except the last end the activation.

| Exit reason | Cause |
| --- | --- |
| `:normal`, `:shutdown` | A stop request, or `server_stop/1`. |
| `{:shutdown, :idle_timeout}` | The idle budget ran out with `idle_policy: :stop`. |
| `{:shutdown, :hibernate}` | A hibernation save succeeded. |
| `{:shutdown, :parent_down}` | The parent stopped, and the policy is `on_parent_exit: :stop`. |
| `{:shutdown, :agent_error}`, `{:shutdown, :max_agent_errors}` | The error policy. |
| `{:shutdown, :error_policy_failed}`, `{:shutdown, :error_policy_timeout}`, `{:shutdown, :invalid_error_policy_result}` | The error policy function raised, ran too long, or returned another value. |
| `{:shutdown, :readiness_timeout}`, `{:shutdown, :persistence_timeout}`, `{:shutdown, :plugin_start_failed}` | Startup did not finish. |
| `{:shutdown, reason}` from startup | A restore or Plugin error, such as `:not_found`. |
| `{:shutdown, :execution_lifecycle_failed}` | The runtime lost track of a Turn: its execution, the Runner, the instance, or a required durable save. |
| `{:shutdown, :effect_lifecycle_failed}` | An effect task died, or a composition change did not become ready. |
| `{:shutdown, :orphan_dispatch_failed}`, `{:shutdown, :orphan_dispatch_timeout}` | The orphan Signal could not be sent. |
| `{:durable_worker_lost, reason}` | The execution of a durable Turn was lost. This is an abnormal exit, so the activation restarts the worker and recovers the Turn. |

## Run under your own supervisor

`Jido.AgentServer.child_spec/1` puts a complete activation under your own supervisor. Pass `:jido` to register it in an instance. The supervisor's child is the activation, so look up the worker by ID.

```elixir
invoice_counter = LifecycleGuide.Counter.instantiate!(id: "shelf-4")

{:ok, _supervisor} =
  Supervisor.start_link([{Jido.AgentServer, agent: invoice_counter, jido: LifecycleGuide.Jido}],
    strategy: :one_for_one
  )

worker = Jido.whereis_agent(LifecycleGuide.Jido, "shelf-4")
:ok = Jido.AgentServer.await_ready(worker)
```

`Jido.AgentServer.start/1` is the lower-level form of `Jido.start_agent/3`. It needs a complete Agent instance and `:jido`.

## Run a bare worker

`Jido.AgentServer.start_link/1` starts a worker linked to the caller, with no activation. Choose it when the calling process must own the link. A linked caller receives the worker's exit, so a `:shutdown` stop also stops a caller that does not trap exits.

```elixir
{:ok, bare} =
  Jido.AgentServer.start_link(
    agent: LifecycleGuide.Counter.instantiate!(id: "shelf-5"),
    jido: LifecycleGuide.Jido
  )

%{activation: :bare} = Jido.AgentServer.status(bare)
nil = Jido.AgentServer.activation(bare)

{:error, :activation_required} =
  Jido.AgentServer.spawn_child(bare, LifecycleGuide.Counter.instantiate!(id: "shelf-6"), :extra)

:ok = Jido.AgentServer.stop(bare, :normal)
```

A bare worker has no restart group and no local checkpoint. It cannot own children, persistence, topology, or runtime Plugins. `start_link/1` returns an error for an Agent or options that need them. Without `:jido`, it needs a `:runner` that names a running Runic Runner configured with the Jido.Persistence.ContinuationStore module.

## Startup options

`Jido.start_agent/3` takes `:id`, `:state`, and the options below. The instance's `:agent_server` option sets the defaults for the runtime options. Unknown or duplicate keys return a `Jido.Error.ValidationError`.

| Option | Default | Meaning |
| --- | --- | --- |
| `:agent` | Required | The Agent instance. `Jido.start_agent/3` sets it. |
| `:jido` | `nil` | The instance. `Jido.start_agent/3` sets it. |
| `:partition` | `nil` | A nonempty string that separates IDs in an instance. |
| `:name` | `nil` | An OTP name for the worker: an atom, `{:global, term}`, or `{:via, module, term}`. |
| `:runner` | The instance's Runner | A named Runic Runner. With `:jido`, it can only name the instance's own Runner. |
| `:turn_timeout` | 60,000 ms | The bound from Turn start to commit. Also configurable with `config :jido, Jido.AgentServer`. |
| `:exec_opts` | `[]` | Execution settings. See [Admission and Deadlines](agent-server-admission.md). |
| `:max_postponed_signals` | 1,000 | The queue limit. |
| `:error_policy` | `:log_only` | The action after a failed Turn. |
| `:error_policy_timeout` | 5,000 ms | The bound on one policy run. |
| `:debug` | `false` | Keep Turn history. |
| `:debug_max_events` | 100 | The history limit, from 1 to 10,000. |
| `:max_directives_per_turn` | 1,000 | The Directive batch limit. |
| `:directive_timeout` | 5,000 ms | The bound on one Directive batch. |
| `:directive_handler` | `nil` | A two-argument function for Directives with no dispatching Plugin. |
| `:default_dispatch` | `nil` | The dispatch for an `Emit` with no target. |
| `:commit_timeout` | 5,000 ms | The bound on Plugin `after_commit/3` callbacks in one Turn. |
| `:readiness_timeout` | 5,000 ms | The bound on Plugin startup and composition changes. |
| `:persistence` | `false` | A store, `{store, options}`, `:inherit`, `nil`, or `false`. |
| `:persistence_mode` | `:create` | `:create` or `:restore`. |
| `:persistence_timeout` | 5,000 ms | The bound on one durable save or restore. |
| `:idle_timeout` | `:infinity` | The idle budget in milliseconds. |
| `:idle_policy` | `:stop` | `:stop`, or `:hibernate` with persistence. |
| `:plugin_runtime_options` | `[]` | Runtime options per Plugin. See [Supervised Resources](../plugins/plugin-supervised-resources.livemd). |

## Next steps

- [Control Activations](inspect-and-control-activations.livemd) drains and reopens a running Agent.
- [Shutdown and Recovery](../operations/shutdown-and-recovery.md) applies this model to a deploy.
