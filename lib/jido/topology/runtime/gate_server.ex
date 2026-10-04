defmodule Jido.Topology.Runtime.GateServer do
  @moduledoc false
  use GenServer
  alias Jido.Topology.{Child, Controller, Resource, Runtime}
  alias Jido.Topology.Runtime.{Gate, Gateway}

  def start_link({config, child} = args),
    do:
      GenServer.start_link(__MODULE__, args,
        name: Controller.name(config.jido, config.id, {:gate, child.key})
      )

  @impl true
  def init({config, child}) do
    tasks = Controller.name(config.jido, config.id, {:gate_tasks, child.key})
    Enum.each(Task.Supervisor.children(tasks), &Task.Supervisor.terminate_child(tasks, &1))

    state = %{
      config: config,
      child: child,
      id: Child.id(config.id, child.key),
      phase: :dormant,
      pid: nil,
      monitor: nil,
      boot: nil,
      queued: [],
      jobs: %{},
      idle: [],
      buses: %{},
      bridge_error: nil,
      failure: nil
    }

    if child.activation == :eager, do: {:ok, state, {:continue, :boot}}, else: {:ok, state}
  end

  @impl true
  def handle_continue(:boot, state), do: {:noreply, boot(state)}

  @impl true
  def handle_call(:status, _, state) do
    state = refresh(state)

    status =
      cond do
        state.phase == :failed -> :failed
        not is_nil(state.bridge_error) -> :degraded
        true -> state.phase
      end

    {:reply, %{id: state.id, status: status, error: state.failure}, state}
  end

  def handle_call(:idle, from, state) do
    state = refresh(state) |> subscribe()
    # A Bus reply is ordered after its prior deliveries to this gate. The
    # local marker then follows those Signals in the gate mailbox.
    Enum.each(state.buses, fn {bus, _} ->
      Gateway.safely(fn -> Jido.Signal.Bus.replay(bus, "**", limit: 0) end)
    end)

    send(self(), {:idle_barrier, from})
    {:noreply, state}
  end

  def handle_call({:call, signal, deadline, opts}, from, state) do
    command = Enum.find(state.child.gate.commands, &(&1.type == signal.type))

    cond do
      command == nil ->
        {:reply, {:error, :command_not_allowed}, state}

      Gateway.check(deadline) != :ok ->
        {:reply, {:error, :activation_timeout}, state}

      state.phase == :failed ->
        {:reply, {:error, state.failure}, state}

      true ->
        state = refresh(state)
        request = {from, command.member, signal, deadline, opts}

        if is_pid(state.pid) do
          {:noreply, dispatch(request, state)}
        else
          {:noreply, boot(%{state | queued: state.queued ++ [request]})}
        end
    end
  end

  @impl true
  def handle_info({ref, result}, %{boot: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, pid} ->
        state = %{state | boot: nil} |> observe(pid) |> phase(:ready)
        state = Enum.reduce(state.queued, %{state | queued: []}, &dispatch/2)
        {:noreply, idle(state)}

      {:error, reason} ->
        Enum.each(state.queued, fn {from, _, _, _, _} ->
          GenServer.reply(from, {:error, reason})
        end)

        {:noreply, %{state | boot: nil, queued: []} |> phase(:degraded) |> idle()}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref), do: complete(ref, result, state)

  def handle_info({:DOWN, ref, :process, _, reason}, %{boot: %{ref: ref}} = state),
    do: handle_info({ref, {:error, reason}}, state)

  def handle_info({:DOWN, ref, :process, _, reason}, %{monitor: ref} = state)
      when not is_nil(ref) do
    state = %{state | pid: nil, monitor: nil}

    if reason in [:normal, :shutdown] or match?({:shutdown, _}, reason) do
      {:noreply, %{state | failure: :child_stopped} |> phase(:failed)}
    else
      Process.send_after(self(), :refresh_child, 10)
      {:noreply, phase(state, :starting)}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    if Map.has_key?(state.buses, pid) do
      Process.send_after(self(), :refresh_child, 10)

      {:noreply,
       %{state | buses: Map.delete(state.buses, pid), bridge_error: :child_bus_unavailable}}
    else
      complete(ref, {:error, reason}, state)
    end
  end

  def handle_info({:idle_barrier, from}, state) do
    {:noreply, idle(%{state | idle: [from | state.idle]})}
  end

  def handle_info(:refresh_child, state) do
    state = refresh(state) |> subscribe()

    if state.phase == :starting or (not is_nil(state.bridge_error) and state.phase != :failed),
      do: Process.send_after(self(), :refresh_child, 100)

    {:noreply, state}
  end

  def handle_info({:signal, %Jido.Signal{} = signal}, state) do
    if Enum.any?(state.child.gate.events, &Jido.Signal.Router.matches?(signal.type, &1)) do
      result =
        Gateway.safely(fn ->
          Runtime.publish(state.config.jido, state.config.id, state.child.gate.to, [signal])
        end)

      error =
        case result do
          {:ok, _} -> nil
          {:error, reason} -> reason
        end

      {:noreply, %{state | bridge_error: error}}
    else
      {:noreply, state}
    end
  end

  defp boot(%{boot: boot} = state) when not is_nil(boot), do: state

  defp boot(state) do
    task =
      task(state, fn ->
        supervisor =
          Controller.name(state.config.jido, state.config.id, {:gate_children, state.child.key})

        options = Runtime.child_options(state.config, state.child)

        case DynamicSupervisor.start_child(supervisor, {Runtime, options}) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            if Gate.whereis_child(state.config.jido, state.config.id, state.child.key) == pid,
              do: {:ok, pid},
              else: {:error, :child_identity_in_use}

          error ->
            error
        end
      end)

    %{state | boot: task} |> phase(:starting)
  end

  defp dispatch({from, member, signal, deadline, opts}, state) do
    task =
      task(state, fn ->
        with :ok <- Gateway.check(deadline),
             do:
               Runtime.call(
                 state.config.jido,
                 state.id,
                 member,
                 signal,
                 Keyword.put(opts, :timeout, Gateway.remaining(deadline))
               )
      end)

    %{state | jobs: Map.put(state.jobs, task.ref, from)}
  end

  defp task(state, fun) do
    Task.Supervisor.async_nolink(
      Controller.name(state.config.jido, state.config.id, {:gate_tasks, state.child.key}),
      fn -> Gateway.safely(fun) end
    )
  end

  defp complete(ref, result, state) do
    case Map.pop(state.jobs, ref) do
      {nil, _} ->
        {:noreply, state}

      {from, jobs} ->
        Process.demonitor(ref, [:flush])
        state = %{state | jobs: jobs} |> refresh() |> subscribe()
        GenServer.reply(from, result)
        {:noreply, idle(state)}
    end
  end

  defp refresh(state) do
    case Gate.whereis_child(state.config.jido, state.config.id, state.child.key) do
      nil ->
        state

      pid ->
        state = if pid == state.pid, do: state, else: observe(state, pid)
        result = Gateway.safely(fn -> Runtime.status(state.config.jido, state.id) end)

        phase =
          case result do
            %{ready?: true} -> :ready
            %{status: :starting} -> :starting
            %{} -> :degraded
            _ -> :starting
          end

        phase(state, phase)
    end
  end

  defp observe(state, pid) do
    if state.monitor, do: Process.demonitor(state.monitor, [:flush])
    %{state | pid: pid, monitor: Process.monitor(pid)}
  end

  defp phase(%{phase: phase} = state, phase), do: state

  defp phase(state, phase) do
    if pid = Runtime.director(state.config.jido, state.config.id) do
      signal =
        Jido.Signal.new!(
          "jido.topology.lifecycle.child.status_changed",
          %{child: state.child.key, id: state.id, status: phase},
          source: "/jido/topology/" <> state.config.id
        )

      Jido.AgentServer.cast(pid, signal)
    end

    %{state | phase: phase}
  end

  defp subscribe(%{pid: nil} = state), do: state
  defp subscribe(%{child: %{gate: %{events: []}}} = state), do: state

  defp subscribe(state) do
    case Runtime.lookup(state.config.jido, state.id, :gateway) do
      nil -> state
      gateway -> subscribe_buses(state, GenServer.call(gateway, :config))
    end
  end

  defp subscribe_buses(state, config) do
    context = %{
      jido: state.config.jido,
      pool: Controller.name(state.config.jido, state.id, :resources)
    }

    Enum.reduce(config.instance.plan.resources, state, fn {_key, resource}, state ->
      pid = Resource.whereis(resource, context)

      if is_pid(pid) and not Map.has_key?(state.buses, pid) do
        case Jido.Signal.Bus.subscribe(pid, "**", target: self()) do
          {:ok, subscription} ->
            %{
              state
              | buses: Map.put(state.buses, pid, {subscription, Process.monitor(pid)}),
                bridge_error: nil
            }

          {:error, reason} ->
            %{state | bridge_error: reason}
        end
      else
        state
      end
    end)
  end

  defp idle(%{boot: nil, queued: [], jobs: jobs} = state) when map_size(jobs) == 0 do
    Enum.each(state.idle, &GenServer.reply(&1, bridge_result(state)))
    %{state | idle: []}
  end

  defp idle(state), do: state
  defp bridge_result(%{bridge_error: nil}), do: :ok
  defp bridge_result(state), do: {:error, state.bridge_error}
  @impl true
  def terminate(_reason, state) do
    Enum.each(state.buses, fn {bus, {subscription, _}} ->
      Gateway.safely(fn -> Jido.Signal.Bus.unsubscribe(bus, subscription) end)
    end)

    :ok
  end
end
