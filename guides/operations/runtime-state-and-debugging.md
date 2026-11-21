# Runtime Debugging

Use this guide when a live Agent is slow, stuck, rejecting work, or gone. It starts from the symptom and tells you what to read. For each status field, see [Status and Turn History](../agent-servers/status-and-history.md).

Run these calls from a remote `IEx` shell on the node that hosts the Agent. Registries are local to a node. Status and read calls stay available while a Turn runs, and they do not read Agent state unless you ask for it.

## Set up an example

The next code starts a dispatch Agent with one Turn held open, so the calls below have something to find.

```elixir
defmodule DebugGuide.Route do
  use Jido.Action,
    name: "debug_guide_route",
    schema: Jido.Joi.object(%{truck: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{truck: truck}, %{agent_state: state} = context) do
    if context[:notify] do
      send(context.notify, {:routing, self()})

      receive do
        :finish -> :ok
      end
    end

    {:ok, %{state | trucks: [truck | state.trucks]}}
  end
end

defmodule DebugGuide.Dispatch do
  use Jido.Agent, name: "debug_guide_dispatch"

  state do
    schema Jido.Joi.object(%{trucks: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/fleet"
    route "truck.route", DebugGuide.Route, as: :route_truck
  end
end

{:ok, _pid} = Jido.start_link(name: DebugGuide.Jido, namespace: "debug-guide/primary")

{:ok, dispatch} =
  Jido.start_agent(DebugGuide.Jido, DebugGuide.Dispatch,
    id: "depot-1",
    partition: "north",
    max_postponed_signals: 1,
    debug: true
  )

route = fn truck -> DebugGuide.Dispatch.route_truck_signal!(%{truck: truck}) end

open_turn =
  Jido.AgentServer.submit(dispatch, route.("truck-1"), context: %{notify: self()})

action =
  receive do
    {:routing, pid} -> pid
  after
    1_000 -> raise "the Turn did not start"
  end
```

## Find the Agent

Look up the Agent with its exact partition. A lookup with no partition finds only Agents with no partition, which is a common reason for a missing Agent.

```elixir
^dispatch = Jido.whereis_agent(DebugGuide.Jido, "depot-1", partition: "north")
nil = Jido.whereis_agent(DebugGuide.Jido, "depot-1")
[{"depot-1", ^dispatch}] = Jido.list_agents(DebugGuide.Jido, partition: "north")
```

`Jido.whereis_agent/3` and `Jido.list_agents/2` return only ready Agents. `Jido.resolve_agent/2` tells you more, because it reports why it found no process:

| Result | Meaning | Do this |
| --- | --- | --- |
| `{:ok, pid}` | The Agent is ready. | Read its status. |
| `{:error, :recovering}` | It is registered and still starting, often while it restores from storage. | Wait, or call `Jido.await_ready/3`. |
| `{:error, :not_found}` | No live process has this Address. | See [The Agent is gone](#the-agent-is-gone). |
| `{:error, :unavailable}` | The instance Registry cannot be read. | See [The Agent is gone](#the-agent-is-gone). |

```elixir
{:ok, address} = Jido.agent_address(DebugGuide.Jido, "depot-1", partition: "north")
{:ok, ^dispatch} = Jido.resolve_agent(DebugGuide.Jido, address)

{:ok, missing} = Jido.agent_address(DebugGuide.Jido, "depot-9", partition: "north")
{:error, :not_found} = Jido.resolve_agent(DebugGuide.Jido, missing)
```

## Read the status

`Jido.AgentServer.status/2` answers most questions. These fields matter first.

```elixir
%Jido.AgentServer.Status{
  phase: :running,
  active: %{turn_id: turn_id, stage: :running, signal_id: signal_id},
  admission: %{mode: :open, postponed: 0, limit: 1, message_queue_len: _mailbox},
  error_count: 0
} = Jido.AgentServer.status(dispatch)

{is_binary(turn_id), is_binary(signal_id)}
```

| Field | Question it answers |
| --- | --- |
| `phase`, `active.stage` | Is a Turn running, and which stage has it reached? |
| `admission.mode` | Is the Agent accepting work? |
| `admission.postponed`, `limit` | How much work waits in the queue? |
| `admission.message_queue_len` | Is the process falling behind its mailbox? |
| `last_outcome`, `error_count` | Did the last Turn commit? How many have failed since the last commit? |
| `last_effect_outcome` | Did the last Directive batch finish? |
| `waits`, `durable_turn` | Is a durable Flow waiting? |

The process also carries a label, which `:observer` and crash reports show.

```elixir
{Jido.AgentServer, "depot-1"} = :proc_lib.get_label(dispatch)
```

To compare Agents, read status for each one. A status call can exit if the server cannot answer in time, so catch the exit in a loop like this.

```elixir
busiest =
  DebugGuide.Jido
  |> Jido.list_agents(partition: "north")
  |> Enum.map(fn {id, pid} ->
    try do
      status = Jido.AgentServer.status(pid, 1_000)
      {id, status.phase, status.admission.postponed, status.admission.message_queue_len}
    catch
      :exit, reason -> {id, :no_answer, reason}
    end
  end)

[{"depot-1", :running, 0, _mailbox_length}] = busiest
```

## Diagnose by symptom

### A call times out

A caller's timeout exits the caller, and it does not stop the Turn. The Turn can still commit after the caller gives up. Read `active` to see the Turn, and use `last_outcome` later to see how it ended. Use `Jido.AgentServer.submit/3` and `Jido.AgentServer.await/2` if a caller should stay alive while it waits.

### A Turn is stuck

Check `active.stage`:

| Stage | Usually waiting on | Next step |
| --- | --- | --- |
| `:starting`, `:running`, `:settling` | Your Action or Flow | Check its external calls. Set a `:timeout` in `:exec_opts`. |
| `:saving` | Your store | Check the store and the persistence metrics. |
| `:effects` | Directive delivery or a Plugin hook. The Turn has committed. | Check the dispatch target. It stops at `:directive_timeout` or `:commit_timeout`. |
| `:waiting` | Input for a durable Flow wait | See [Flow Waits](../flow-runtime/flow-waits.md). |

A stuck Turn ends at `:turn_timeout`, which defaults to 60 seconds. To end it now, cancel that exact Turn. `Jido.AgentServer.cancel_turn/3` waits for its work to stop, and the Turn's caller gets `{:error, :cancelled}`. The ID check protects you from cancelling a later Turn by mistake.

```elixir
{:error, :stale_turn} = Jido.AgentServer.cancel_turn(dispatch, "older-turn-id")
:ok = Jido.AgentServer.cancel_turn(dispatch, turn_id)

{:error, :cancelled} = Jido.AgentServer.await(open_turn)
false = Process.alive?(action)

%{status: :cancelled, committed?: false} = Jido.AgentServer.status(dispatch).last_outcome
{:error, :not_running} = Jido.AgentServer.cancel(dispatch)
```

Cancel works before commit only. Work after a commit runs to its own limit. See [Cancel Turns](../agent-servers/cancel-turns.livemd).

### Callers get admission errors

| Error | Cause | Do this |
| --- | --- | --- |
| `{:overloaded, %{limit: limit, postponed: count}}` | The queue is full. | Find the slow Turn. Add Agents, or raise `:max_postponed_signals` only if callers can wait. |
| `:admission_timeout` | The request waited too long for its Turn. | Same as above. No work started. |
| `:quiesced` | Admission is closed. | Read `admission.mode`. Call `Jido.AgentServer.resume/2` if the drain is over. |
| `:not_ready` | The server is still starting. | Call `Jido.AgentServer.await_ready/2`. |
| `:reentrant_turn` | The running Turn called its own Agent. | Fix the code. Return a Directive in place of the call. |

`message_queue_len` covers what the queue limit does not, because the limit bounds postponed Turns and not the mailbox. A cast also rejects silently: it returns `:ok` even when the Turn is not admitted. Use `call` or `submit` if the sender must know.

If `admission.mode` is `:blocked`, an uncertain hibernation save closed the Agent. `Jido.AgentServer.resume/2` returns `{:error, :unsafe_resume}`. Stop it and activate it again, which reads the stored record.

### Turns fail or effects are lost

Read `last_outcome` and `last_effect_outcome` together. A successful Turn with a failed effect has `last_outcome.status` `:succeeded` and `last_effect_outcome.status` `:failed`. The state is committed, and the Signal did not arrive.

Each failed Turn's error goes to its caller. A cast has no caller, so set an `:error_policy` that reports failures, or watch telemetry. History gives you the recent pattern. It is opt-in, so start the Agent with `debug: true` before you need it, and raise `:debug_max_events` if the default 100 entries are too few.

```elixir
[%{status: :cancelled, stage: stage}] = Jido.AgentServer.history(dispatch)
is_atom(stage)
```

### The Agent is gone

Status cannot help when no process exists. Check these causes:

1. **Restart limit.** An activation allows three restarts in five seconds, and then it stops for good. Look for repeated crash reports. In-memory state is gone. A durable Agent can be activated again.
2. **Idle stop.** An Agent with `:idle_timeout` stops when unused. Check its options.
3. **Terminal Turn.** A `:stop_on_error` or `{:max_errors, count}` policy, a `Jido.Agent.Directive.server_stop/1`, or a failed required write stops the activation.
4. **Instance restart.** If the instance Registry, Runner, or Agent supervisor dies, every Agent in that instance stops. See [Shutdown and Recovery](shutdown-and-recovery.md#what-happens-on-each-failure).

If an activation fails to start again, its error reports why. Common causes are a missing or deleted record and changed Agent code. See [Durability Model](../durability/durability-model.md).

## Watch a live node

To see Turn results as they happen, turn on the semantic logger for a while. Your `Logger` level has to allow `:debug` for non-error lines.

<!-- partial -->
```elixir
Logger.configure(level: :debug)
Application.put_env(:jido, :telemetry, semantic_log_mode: :all)

# Put these back when you finish.
Application.put_env(:jido, :telemetry, semantic_log_mode: :errors)
Logger.configure(level: :info)
```

These lines use bounded fields, so they hold no Agent state or Signal data. See [Telemetry and Tracing](telemetry-tracing-and-logs.md#log-modes).

To read committed state, call `Jido.AgentServer.agent/2`. It returns the full Agent, so treat its output as sensitive. Avoid `:sys.get_state/1` on an AgentServer, because that call depends on private data with no stable shape.

## Next steps

- [Status and Turn History](../agent-servers/status-and-history.md)
- [Control Activations](../agent-servers/inspect-and-control-activations.livemd)
- [Debug Flows](../flow-runtime/debugging-flows.md)
