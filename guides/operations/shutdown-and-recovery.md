# Shutdown and Recovery

Follow this guide to stop a Jido instance without losing work you can save, and to bring your Agents back after a stop or a crash. For the rules on durable data, see [Recovery Limits](../durability/recovery-and-effect-limits.md).

## What a stop does to running work

Stopping an AgentServer does not wait for its Turn. These apply whether you call `Jido.stop/1`, stop your application, or receive a shutdown from a supervisor:

- The running Turn ends. Telemetry reports `status: :indeterminate`, and its caller gets an error.
- Queued requests are dropped, and their callers get errors.
- Effects still in progress are recorded as `:indeterminate`. Some may already have happened.
- A non-durable Agent's state is gone. A durable Agent keeps its last committed revision.

Build the example used in this guide, and watch a stop end a Turn.

```elixir
defmodule ShutdownGuide.Ship do
  use Jido.Action,
    name: "shutdown_guide_ship",
    schema: Jido.Joi.object(%{parcel: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{parcel: parcel}, %{agent_state: state} = context) do
    if context[:notify] do
      send(context.notify, {:shipping, self()})

      receive do
        :finish -> :ok
      end
    end

    {:ok, %{state | shipped: state.shipped ++ [parcel]}}
  end
end

defmodule ShutdownGuide.Dock do
  use Jido.Agent, name: "shutdown_guide_dock"

  state do
    schema Jido.Joi.object(%{shipped: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/shipping"
    route "parcel.ship", ShutdownGuide.Ship, as: :ship
  end
end

ship = fn parcel -> ShutdownGuide.Dock.ship_signal!(%{parcel: parcel}) end

open_turn = fn server ->
  pending = Jido.AgentServer.submit(server, ship.("open"), context: %{notify: self()})

  receive do
    {:shipping, action} -> {pending, action}
  after
    1_000 -> raise "the Turn did not start"
  end
end

{:ok, _pid} = Jido.start_link(name: ShutdownGuide.Abrupt)
{:ok, dock} = Jido.start_agent(ShutdownGuide.Abrupt, ShutdownGuide.Dock, id: "dock-1")
{pending, _action} = open_turn.(dock)

:ok = Jido.stop(ShutdownGuide.Abrupt)

{:error, %Jido.Error.ExecutionError{message: "Agent server stopped before the turn replied"}} =
  Jido.AgentServer.await(pending)
```

## Drain an instance

To let work finish, close admission first. `Jido.AgentServer.quiesce/2` rejects new and queued requests with `:quiesced` and waits for the running Turn and its effects. `Jido.AgentServer.hibernate/2` does the same, and then saves the Agent and stops it.

| Call | After it returns `:ok` | Use it for |
| --- | --- | --- |
| `Jido.AgentServer.quiesce/2` | The server is alive, settled, and closed. | Non-durable Agents, or a pause you may undo with `Jido.AgentServer.resume/2`. |
| `Jido.AgentServer.hibernate/2` | The record is saved and the activation has stopped. | Durable Agents. |

Both accept `timeout:`, which defaults to 5,000 ms, and `active: :cancel`, which cancels pre-commit work and lets accepted saves and effects finish.

Jido has no drain function for a whole instance, so write one. Drain Agents at the same time, because each one can use its full budget. A status call or control call can exit if a server does not answer, so handle that case too. Pass each partition you use, because `Jido.list_agents/2` reads one at a time.

```elixir
defmodule ShutdownGuide.Drain do
  # Returns {drained, failed}, where failed lists {agent_id, reason}.
  def run(instance, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    partition = Keyword.get(opts, :partition)

    instance
    |> Jido.list_agents(partition: partition)
    |> Task.async_stream(fn {id, server} -> {id, drain(server, timeout, opts)} end,
      max_concurrency: Keyword.get(opts, :max_concurrency, 64),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.split_with(fn {_id, result} -> result == :ok end)
    |> then(fn {drained, failed} -> {length(drained), failed} end)
  end

  defp drain(server, timeout, opts) do
    if Keyword.get(opts, :durable, false),
      do: Jido.AgentServer.hibernate(server, timeout: timeout),
      else: Jido.AgentServer.quiesce(server, timeout: timeout)
  catch
    :exit, reason -> {:exit, reason}
  end
end
```

An expired budget leaves admission closed and returns `{:error, :quiesce_timeout}`, so the Agent takes no new work while you decide. The next example drains one Agent that finishes in time and one with a Turn that does not.

```elixir
{:ok, _pid} = Jido.start_link(name: ShutdownGuide.Drained)
{:ok, ready} = Jido.start_agent(ShutdownGuide.Drained, ShutdownGuide.Dock, id: "ready")
{:ok, busy} = Jido.start_agent(ShutdownGuide.Drained, ShutdownGuide.Dock, id: "busy")
{busy_turn, action} = open_turn.(busy)

{1, [{"busy", {:error, :quiesce_timeout}}]} =
  ShutdownGuide.Drain.run(ShutdownGuide.Drained, timeout: 20)

{:error, :quiesced} = Jido.AgentServer.call(ready, ship.("late"))
{:error, :quiesced} = Jido.AgentServer.call(busy, ship.("late"))

send(action, :finish)
{:ok, %{state: %{shipped: ["open"]}}, []} = Jido.AgentServer.await(busy_turn)

{2, []} = ShutdownGuide.Drain.run(ShutdownGuide.Drained, timeout: 1_000)

:ok = Jido.stop(ShutdownGuide.Drained)
```

During a drain, `Jido.AgentServer.cast/3` still returns `:ok`, and the Signal is dropped. Stop sending work to the node before you drain it.

For a durable Agent, read each `hibernate` failure. Its error is `%{reason: reason, resumable?: boolean}`. A conflict or an uncertain save keeps the Agent closed, and a later resume returns `{:error, :unsafe_resume}`. The stored record is still the source of truth, so let it stop and activate it on restart.

### Run the drain when your application stops

Your application's `prep_stop/1` callback runs before its supervision tree stops. First stop new traffic, then drain.

<!-- partial -->
```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def prep_stop(state) do
    MyApp.Traffic.stop_accepting()
    {_drained, failed} = MyApp.Drain.run(MyApp.Jido, durable: true, timeout: 20_000)
    if failed != [], do: Logger.warning("Agents did not drain: #{inspect(failed)}")
    state
  end
end
```

Your platform's stop timeout must be longer than the whole sequence. Anything still running when the BEAM exits ends as an abrupt stop.

## Set supervisor time budgets

These times decide when OTP stops waiting.

| Process | Budget | Then |
| --- | --- | --- |
| Instance supervisor, as a child of your tree | 10,000 ms to stop | Your supervisor kills it. |
| AgentServer | 10,000 ms to stop | Its activation supervisor kills it. |
| Activation restart limit | 3 restarts in 5 seconds | The activation stops and is not restarted. |
| Instance Agent supervisor restart limit | 1,000 restarts in 5 seconds | The instance's Agent supervisor exits. |
| Instance restart limit | The OTP default, 3 restarts in 5 seconds | The instance exits, and your supervisor decides. |
| `Jido.start_link/1` wait for an old instance's children | 10,000 ms | It returns `{:error, {:previous_instance_still_stopping, pid}}`. |

To allow a longer stop, override the child spec. A longer value does not make a Turn wait, because Turns end at shutdown. It gives slow `terminate` work and many Agents more time.

```elixir
defmodule ShutdownGuide.Patient do
  use Jido, otp_app: :shutdown_guide
end

%{shutdown: 30_000, type: :supervisor} = Supervisor.child_spec(ShutdownGuide.Patient, shutdown: 30_000)
```

## What happens on each failure

| Failure | What OTP does | Agent state | What you do |
| --- | --- | --- | --- |
| AgentServer crash | The activation restarts it. | Restored: from the local checkpoint, or from the store if durable. | Nothing. Callers retry. |
| More than 3 restarts in 5 seconds | The activation stops and stays stopped. | Non-durable state is gone. The record stays. | Fix the cause, and activate again. |
| Activation supervisor killed | The Agent supervisor restarts it. | Non-durable state is gone, because the checkpoint died with it. A durable Agent restores. | Nothing, for a durable Agent. |
| Instance Registry, Runner, or Agent supervisor dies | Every Agent in the instance stops, and they do not restart. The instance can exit too. | Non-durable state is gone. Records stay. | Activate Agents again. |
| Instance supervisor exits | Your supervisor restarts it, with no Agents. | Same. | Activate Agents again. |
| BEAM loss | Your platform restarts it. | Only what your store kept. | Activate Agents again. |

This example shows the first two rows for a non-durable Agent.

```elixir
{:ok, _pid} = Jido.start_link(name: ShutdownGuide.Crashes)
{:ok, crashing} = Jido.start_agent(ShutdownGuide.Crashes, ShutdownGuide.Dock, id: "dock-1")
{:ok, _agent, []} = Jido.AgentServer.call(crashing, ship.("first"))

activation = Jido.AgentServer.activation(crashing)
activation_monitor = Process.monitor(activation)

await_worker = fn await_worker, old, attempts ->
  case Jido.whereis_agent(ShutdownGuide.Crashes, "dock-1") do
    pid when is_pid(pid) and pid != old -> pid
    _other when attempts > 0 ->
      Process.sleep(5)
      await_worker.(await_worker, old, attempts - 1)
    _other -> nil
  end
end

Process.exit(crashing, :kill)
restarted = await_worker.(await_worker, crashing, 200)

%{shipped: ["first"]} = Jido.AgentServer.agent(restarted).state
1 = Jido.AgentServer.status(restarted).state_version

Enum.reduce_while(1..10, restarted, fn _attempt, worker ->
  Process.exit(worker, :kill)

  case await_worker.(await_worker, worker, 40) do
    nil -> {:halt, :stopped}
    next -> {:cont, next}
  end
end)

:shutdown =
  receive do
    {:DOWN, ^activation_monitor, :process, ^activation, reason} -> reason
  after
    1_000 -> :still_running
  end

nil = Jido.whereis_agent(ShutdownGuide.Crashes, "dock-1")
:ok = Jido.stop(ShutdownGuide.Crashes)
```

## Restart Agents with the instance

Jido has no recovery scanner. Your application keeps the list of Agents that should be running and activates them. Do this each time the instance starts, including a restart after a crash.

Put the instance and a recovery task under a `:rest_for_one` supervisor. When the instance restarts, OTP also restarts everything after it. This example kills the instance and shows the durable Agent come back on its own. The kill logs supervisor errors, which you should expect here.

```elixir
defmodule ShutdownGuide.Instance do
  use Jido,
    otp_app: :shutdown_guide,
    namespace: "shutdown-guide/primary",
    persistence: {Jido.Persistence.ETS, table: :shutdown_guide_store}
end

defmodule ShutdownGuide.Recovery do
  use Task, restart: :transient

  def start_link(ids), do: Task.start_link(__MODULE__, :run, [ids])

  def run(ids) do
    for id <- ids do
      {:ok, ref} = Jido.agent_ref(ShutdownGuide.Instance, id)
      {:ok, _server} = Jido.activate_agent(ShutdownGuide.Instance, ref, ShutdownGuide.Dock)
    end
  end
end

{:ok, runtime} =
  Supervisor.start_link(
    [ShutdownGuide.Instance, {ShutdownGuide.Recovery, ["dock-1"]}],
    strategy: :rest_for_one
  )

await_agent = fn await_agent, old, attempts ->
  case Process.whereis(ShutdownGuide.Instance) && Jido.whereis_agent(ShutdownGuide.Instance, "dock-1") do
    pid when is_pid(pid) and pid != old -> pid
    _other when attempts > 0 ->
      Process.sleep(10)
      await_agent.(await_agent, old, attempts - 1)
    _other -> nil
  end
end

durable = await_agent.(await_agent, nil, 200)
:ok = Jido.AgentServer.await_ready(durable)
{:ok, _agent, []} = Jido.AgentServer.call(durable, ship.("kept"))

Process.exit(Process.whereis(ShutdownGuide.Instance), :kill)

recovered = await_agent.(await_agent, durable, 500)
:ok = Jido.AgentServer.await_ready(recovered)
%{shipped: ["kept"]} = Jido.AgentServer.agent(recovered).state

Supervisor.stop(runtime)
```

In a real system, read the list of IDs from your own data inside `run/1`, and handle an activation error for one Agent without failing the others. A Flow Turn that was running resumes when its Agent activates. An Action route Turn does not. See [Recovery Limits](../durability/recovery-and-effect-limits.md).

## Recovery checklist

After a crash or an unplanned restart:

1. Check that the instance runs, and compare `Jido.agent_count/2` for each partition with what you expect.
2. Check activation errors. A record that fails its checks is not replaced, so it needs your attention.
3. Check the store for `conflict` and `indeterminate` results. See [Metrics and OTel](metrics-and-open-telemetry.md#what-to-alert-on).
4. Check external systems for repeated or missing work. A step can run again after a crash, and an effect may not have run.
5. Tell callers to retry. Queued Signals and caller handles do not survive.

## Next steps

- [Recovery Limits](../durability/recovery-and-effect-limits.md)
- [Hibernate and Thaw](../agent-servers/hibernate-thaw-and-activate.md)
- [Test Jido Systems](test-jido-systems.livemd)
