defmodule Jido.Topology.Runtime.Gateway do
  @moduledoc false
  use GenServer
  alias Jido.Topology.{Controller, Runtime}
  alias Jido.Topology.Controller.TargetStore

  def start_link(config),
    do:
      GenServer.start_link(__MODULE__, config,
        name: Controller.name(config.jido, config.id, :gateway)
      )

  def request(jido, id, request, opts) do
    with {:ok, timeout} <- timeout(opts) do
      case Runtime.lookup(jido, id, :gateway) do
        nil -> {:error, :topology_not_running}
        pid -> bounded_call(pid, {:request, request, deadline(timeout), options(opts)}, timeout)
      end
    end
  end

  def options(opts) when is_map(opts), do: Map.to_list(opts)
  def options(opts), do: opts

  def timeout(opts) do
    with {:ok, attrs} <- Jido.Agent.Authoring.attrs(opts),
         :ok <- Jido.Agent.Authoring.keys(attrs, [:timeout, :context]) do
      case Map.get(attrs, :timeout, 5_000) do
        :infinity -> {:ok, :infinity}
        timeout when is_integer(timeout) and timeout > 0 -> {:ok, timeout}
        0 -> {:error, :activation_timeout}
        _ -> Jido.Agent.Authoring.error("Expected a non-negative timeout or :infinity")
      end
    end
  end

  def bounded_call(pid, request, timeout) do
    GenServer.call(pid, request, if(timeout == :infinity, do: timeout, else: timeout + 100))
  catch
    :exit, {:timeout, _} -> {:error, :activation_timeout}
    :exit, _ -> {:error, :topology_not_running}
  end

  def deadline(:infinity), do: :infinity
  def deadline(timeout), do: System.monotonic_time(:millisecond) + timeout
  def remaining(:infinity), do: :infinity
  def remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  def check(deadline) do
    if remaining(deadline) == 0, do: {:error, :activation_timeout}, else: :ok
  end

  def safely(fun) do
    fun.()
  rescue
    error -> {:error, error}
  catch
    :exit, {:timeout, _} -> {:error, :activation_timeout}
    :exit, reason -> {:error, reason}
  end

  @impl true
  def init(config) do
    tasks = Controller.name(config.jido, config.id, :runtime_tasks)
    Enum.each(Task.Supervisor.children(tasks), &Task.Supervisor.terminate_child(tasks, &1))

    with {:ok, instance, _, _, _} <- TargetStore.load(config.jido, config.instance) do
      {:ok, %{config: %{config | instance: instance}, jobs: %{}}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:config, _, state), do: {:reply, state.config, state}

  def handle_call({:request, request, deadline, opts}, from, state) do
    task =
      Task.Supervisor.async_nolink(
        Controller.name(state.config.jido, state.config.id, :runtime_tasks),
        fn -> safely(fn -> execute(state.config, request, deadline, opts) end) end
      )

    {:noreply, %{state | jobs: Map.put(state.jobs, task.ref, from)}}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref), do: complete(ref, result, state)

  def handle_info({:DOWN, ref, :process, _, reason}, state),
    do: complete(ref, {:error, reason}, state)

  defp complete(ref, result, state) do
    case Map.pop(state.jobs, ref) do
      {nil, _} ->
        {:noreply, state}

      {from, jobs} ->
        Process.demonitor(ref, [:flush])
        GenServer.reply(from, result)
        {:noreply, %{state | jobs: jobs}}
    end
  end

  defp execute(config, {:call, target, signal}, deadline, opts) do
    with :ok <- ready(config, target, deadline),
         pid when is_pid(pid) <- Runtime.whereis_member(config.jido, config.id, target),
         :ok <- check(deadline) do
      Jido.AgentServer.call(pid, signal, Keyword.put(opts, :timeout, remaining(deadline)))
    else
      nil -> {:error, :member_unavailable}
      error -> error
    end
  end

  defp execute(config, {:publish, bus, signals}, deadline, _opts) do
    with :ok <- ready(config, {:resource, bus}, deadline),
         pid when is_pid(pid) <- Runtime.whereis_bus(config.jido, config.id, bus),
         :ok <- check(deadline) do
      Jido.Signal.Bus.publish(pid, signals)
    else
      nil -> {:error, :resource_unavailable}
      error -> error
    end
  end

  defp ready(config, target, deadline) do
    with :ok <- check(deadline),
         controller when is_pid(controller) <- Runtime.controller(config.jido, config.id),
         :ok <- Controller.activate(controller, target, remaining(deadline)),
         :ok <- Controller.await_target(controller, target, remaining(deadline)) do
      :ok
    else
      nil -> {:error, :topology_not_running}
      error -> error
    end
  end
end
