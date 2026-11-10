# OTP Concepts for Jido

Jido uses ordinary OTP parts: `:gen_statem`, supervisors, tasks, monitors, a `Registry`, and ETS. This guide shows where each one appears and what it means for your code. It assumes you know what a process and a supervisor are. If you come from Node.js, read [Node.js and the BEAM](../from-typescript/nodejs-and-the-beam.md) first.

## An Agent is a value until you start it

A `Jido.Agent` is an immutable struct. It holds no PID, and it needs no process to run a Turn. See [Pure or Live Execution](pure-or-live-execution.md).

A live Agent is a process that holds one of those values and replaces it at each commit. The examples in this guide use this Agent.

```elixir
defmodule OtpGuide.PackOrder do
  use Jido.Action,
    name: "otp_guide_pack_order",
    schema: Jido.Joi.object(%{order_id: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{order_id: order_id}, %{agent_state: state, notify: notify}) do
    send(notify, {:packing, order_id, self()})

    receive do
      :finish -> {:ok, %{state | packed: [order_id | state.packed]}}
    end
  end
end

defmodule OtpGuide.Packer do
  use Jido.Agent, name: "packer"

  state do
    schema Jido.Joi.object(%{packed: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/warehouse/packer"
    route "order.pack", OtpGuide.PackOrder, as: :pack
  end
end

{:ok, _instance} = Jido.start(name: OtpGuide.Jido)
{:ok, packer} = Jido.start_agent(OtpGuide.Jido, OtpGuide.Packer, id: "packer-1")
:ok = Jido.AgentServer.await_ready(packer)

pack = fn order_id -> OtpGuide.Packer.pack_signal!(%{order_id: order_id}) end
```

## The AgentServer is a state machine

`Jido.AgentServer` implements `:gen_statem`. Its states are the phases of a Turn, such as `:idle`, `:running`, and `:effects`. `Jido.AgentServer.status/2` reports them.

A state machine suits this job because of one feature, postponing. When a Turn request arrives during another Turn, the server marks it as postponed. OTP keeps the message and delivers it again at the next state change. Requests therefore wait in arrival order, and reads pass them by.

`:max_postponed_signals` limits this queue, with a default of 1,000. Beyond that limit, a request gets `{:error, {:overloaded, details}}`, and a cast is dropped and logged. See [Admission and Deadlines](../agent-servers/agent-server-admission.md).

## Work runs outside the server process

The server process only decides what happens next. It hands slow work to other processes and waits for a message, so it can always answer reads and cancel requests.

| Work | Process |
| --- | --- |
| Turn order, admission, reads, the commit swap | The AgentServer process |
| Plugin `prepare/2` and `admit/3`, route selection, a store write, each Directive | One short-lived task for each stage, linked to the server |
| Your Action or Flow | A Runic Worker and its tasks, under the instance's Runner |
| `Jido.Agent.cmd/3` and `Jido.Exec.run/4` | An unlinked task under a task supervisor, with the caller blocked |

So `self()` in a Turn's Action is never the server, and it is never your caller. Pass a PID through context when an Action must send a message, as `PackOrder` does.

```elixir
pending = Jido.AgentServer.submit(packer, pack.("o-1"), context: %{notify: self()})

action =
  receive do
    {:packing, "o-1", pid} -> pid
  after
    1_000 -> raise "the Action did not start"
  end

true = action != packer and action != self()

# The server answers reads during the Turn.
%{phase: :running, active: %{stage: :running}} = Jido.AgentServer.status(packer)
%{packed: []} = Jido.AgentServer.agent(packer).state

# A second request waits in the queue.
queued = Jido.AgentServer.submit(packer, pack.("o-2"), context: %{notify: self()})

Enum.find(1..200, fn _attempt ->
  Process.sleep(5)
  Jido.AgentServer.status(packer).admission.postponed == 1
end)

send(action, :finish)
{:ok, %{state: %{packed: ["o-1"]}}, []} = Jido.AgentServer.await(pending)

receive do
  {:packing, "o-2", second} -> send(second, :finish)
after
  1_000 -> raise "the queued Turn did not start"
end

{:ok, %{state: %{packed: ["o-2", "o-1"]}}, []} = Jido.AgentServer.await(queued)
```

An Action that calls `Jido.AgentServer.call/3` on its own Agent would wait for itself. The server detects this case and returns `{:error, :reentrant_turn}`.

## Calls, casts, and timeouts

The request functions are thin layers over OTP messaging, so OTP's rules apply:

| Function | OTP form | The caller gets |
| --- | --- | --- |
| `Jido.AgentServer.call/3` | `:gen_statem.call/3` | The Turn result. An exit if the wait runs out or the server dies. |
| `Jido.AgentServer.submit/3` with `Jido.AgentServer.await/2` | `:gen_statem.send_request/2` | The Turn result. `{:error, :timeout}` if the wait runs out, and you can wait again. An error if the server dies. |
| `Jido.AgentServer.cast/3` | `:gen_statem.cast/2` | `:ok`, even if the server is gone. The Turn's result is not returned. |

A failed Turn is a return value. A caller that stops waiting is an exit, as with any OTP call. The Turn does not depend on the caller and keeps going, so use `Jido.AgentServer.cancel/2` to stop it.

```elixir
slow = Task.async(fn ->
  try do
    Jido.AgentServer.call(packer, pack.("o-3"), timeout: 20, context: %{notify: self()})
  catch
    :exit, {:timeout, _call} ->
      receive do
        {:packing, "o-3", pid} -> {:gave_up, pid}
      end
  end
end)

{:gave_up, still_running} = Task.await(slow)
true = Process.alive?(still_running)
send(still_running, :finish)
```

## The process tree

Three levels of supervisors own these processes.

The `:jido` application starts shared services when your app boots. It does not start any Agents.

A **Jido instance** is a supervisor you start, normally by adding a `use Jido` module to your application's supervision tree. It holds a Runner, a task supervisor, a `Registry`, and a `DynamicSupervisor` for Agents. Its strategy is `:one_for_one`.

An **activation** is a supervisor for one live Agent, with the AgentServer worker as its child. Plugin runtimes, topology buses, and owned child Agents join it as needed. [Agent Lifecycle](../agent-servers/agent-activation-control.md#the-process-tree) shows the tree.

These settings shape how a live Agent fails:

| Setting | Where | Effect |
| --- | --- | --- |
| `strategy: :one_for_all` | Activation | A worker crash also restarts Plugin runtimes and stops owned children. They depend on each other. |
| `restart: :transient` | Worker and activation | Only an abnormal exit restarts. `:normal`, `:shutdown`, and `{:shutdown, term}` do not. |
| `significant: true`, `auto_shutdown: :any_significant` | Worker and activation | When the worker stops on purpose, the activation stops too. No empty activation stays behind. |
| `max_restarts: 3, max_seconds: 5` | Activation | A worker that keeps crashing ends the activation. A supervisor exits with `:shutdown` at this limit, so the transient activation does not restart either. |

## A crash loses work but no commit

An activation owns an ETS table, and the commit writes the Agent and revision to it. The table outlives the worker, so a new worker starts from the last commit. With persistence, the new worker reads from the store. The Turn in progress and the queue live in the old process, so they are gone.

```elixir
pending = Jido.AgentServer.submit(packer, pack.("o-4"), context: %{notify: self()})

doomed =
  receive do
    {:packing, "o-4", pid} -> pid
  after
    1_000 -> raise "the Action did not start"
  end

activation = Jido.AgentServer.activation(packer)
action_monitor = Process.monitor(doomed)
Process.exit(packer, :kill)

# The caller gets an error, and the owned Action stops.
{:error, %Jido.Error.ExecutionError{}} = Jido.AgentServer.await(pending)

receive do
  {:DOWN, ^action_monitor, :process, ^doomed, _reason} -> :stopped
after
  1_000 -> raise "the Action kept running"
end

replacement =
  Enum.find_value(1..200, fn _attempt ->
    Process.sleep(5)

    case Jido.whereis_agent(OtpGuide.Jido, "packer-1") do
      pid when is_pid(pid) and pid != packer -> pid
      _not_ready -> nil
    end
  end)

# Same activation, new worker, last committed state.
^activation = Jido.AgentServer.activation(replacement)
%{agent: %{state: %{packed: ["o-3", "o-2", "o-1"]}}, state_version: 3} = Jido.AgentServer.snapshot(replacement)
```

The Action stopped because Runic ties a Worker's execution to its owner. A step that had already called an external system stays done. See [Recovery Limits](../durability/recovery-and-effect-limits.md).

## Do not hold on to a PID

The worker's PID changes at each restart, as the example above shows. Look up an Agent by ID when you need it. Each instance has its own `Registry`, keyed by Agent ID and partition, so an ID is unique within an instance and partition. `Jido.whereis_agent/3` returns `nil` until the Agent is ready.

Use a `Jido.Agent.Ref` for a name you can store, and let `Jido.call/4` find the current process. See [Start and Address Agents](../agent-servers/start-and-address-live-agents.livemd).

## Monitors tie the parts together

The worker traps exits and monitors the processes it depends on. Each one has a defined result:

| The worker monitors | When it goes down |
| --- | --- |
| Its instance, `Registry`, and registration guard | The worker stops with `{:shutdown, :execution_lifecycle_failed}`. |
| The Runner | The worker stops with the same reason. |
| A running Worker | The worker stops with the same reason, unless the Turn is durable. A durable Turn exits abnormally, so the worker restarts and resumes it. |
| A stage task | The worker stops with the same reason. |
| Its parent activation | `:on_parent_exit` decides. See [Child Agent Adoption](../agent-servers/child-agents-and-adoption.md). |
| A child's activation | The worker forgets the child unless a restart is expected. |
| An attached owner | The worker drops the owner, and the idle timer can start. See [Control Activations](../agent-servers/inspect-and-control-activations.livemd). |

During effects, the first four rows use `{:shutdown, :effect_lifecycle_failed}` instead. Trapping exits also means the worker runs `terminate/3` when its supervisor stops it, which cancels any running execution.

## Related

- [Life of a Signal](signal-to-effects.md) follows one request through these processes.
- [Definitions and Runtime](definitions-instances-activations.md) separates definitions, values, and activations.
- [Agent Lifecycle](../agent-servers/agent-activation-control.md) lists every exit reason.
