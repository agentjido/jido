defmodule Jido.Topology.Controller.Owner do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.Telemetry.Semantic
  alias Jido.Topology.Controller.TargetStore

  require Logger

  def start(jido, controller, topology_id) do
    name = Jido.Topology.Controller.name(jido, topology_id, :owner)

    # A replacement instance must not load a target while the old instance
    # still owns cleanup of that target or its remote members.
    with :ok <- await_previous(GenServer.whereis(name)) do
      caller = self()
      token = make_ref()

      with {:ok, pid} <-
             Task.Supervisor.start_child(Jido.task_supervisor_name(jido), fn ->
               {:via, Registry, {registry, key}} = name
               {:ok, _} = Registry.register(registry, key, nil)
               ref = Process.monitor(controller)
               send(caller, {token, :ready})
               await_down(jido, controller, topology_id, ref, %{}, [])
             end) do
        ref = Process.monitor(pid)

        receive do
          {^token, :ready} ->
            Process.demonitor(ref, [:flush])
            {:ok, pid}

          {:DOWN, ^ref, :process, ^pid, reason} ->
            {:error, reason}
        after
          5_000 ->
            Process.demonitor(ref, [:flush])
            Process.exit(pid, :kill)
            {:error, :ownership_start_timeout}
        end
      end
    end
  end

  defp await_previous(nil), do: :ok

  defp await_previous(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      5_000 ->
        Process.demonitor(ref, [:flush])
        {:error, :ownership_cleanup_pending}
    end
  end

  # Local members are OTP children. Only remote members need watcher cleanup.
  def track(owner, pid) when node(owner) != node(pid), do: send(owner, {:track, pid})
  def track(_owner, _pid), do: :ok

  # This is an observation barrier for the settlement event. OTP performs
  # local shutdown; the watcher never stops or scans local Agents.
  def observe_tree(owner, supervisors), do: send(owner, {:local_tree, supervisors})

  defp await_down(jido, controller, topology_id, ref, tracked, supervisors) do
    receive do
      {:track, pid} when is_pid(pid) ->
        await_down(jido, controller, topology_id, ref, Map.put(tracked, pid, true), supervisors)

      {:local_tree, supervisors} ->
        await_down(jido, controller, topology_id, ref, tracked, supervisors)

      {:DOWN, ^ref, :process, ^controller, reason} ->
        Enum.each(supervisors, &await_supervisor/1)
        cleanup(jido, topology_id, drain_tracked(tracked), reason)
    end
  end

  defp await_supervisor(pid) do
    ref = Process.monitor(pid)
    receive do: ({:DOWN, ^ref, :process, ^pid, _reason} -> :ok)
  end

  defp drain_tracked(tracked) do
    receive do
      {:track, pid} -> drain_tracked(Map.put(tracked, pid, true))
      {:local_tree, _supervisors} -> drain_tracked(tracked)
    after
      0 -> tracked
    end
  end

  defp cleanup(jido, topology_id, tracked, reason) do
    candidates = Map.keys(tracked)

    {stopped, failed} =
      Enum.reduce(candidates, {0, 0}, fn pid, {stopped, failed} ->
        if owned?(pid, topology_id) do
          case stop_agent(jido, pid) do
            :ok ->
              {stopped + 1, failed}

            {:error, :not_found} ->
              {stopped, failed}

            error ->
              Logger.error(
                "Topology-owned Agent cleanup failed for #{topology_id} / #{inspect(pid)} after #{inspect(reason)}: #{inspect(error)}"
              )

              {stopped, failed + 1}
          end
        else
          {stopped, failed}
        end
      end)

    _ = TargetStore.forget_local(jido, topology_id)

    Semantic.point(
      [:jido, :topology, :ownership, :settled],
      %{
        topology_id: topology_id,
        topology_operation: :cleanup,
        status: if(failed == 0, do: :ok, else: :error)
      },
      %{component_count: stopped + failed, ready_count: stopped, failed_count: failed}
    )
  end

  defp owned?(pid, topology_id) do
    agent = :erpc.call(node(pid), AgentServer, :agent, [pid], 5_000)

    match?(%{id: ^topology_id}, Map.get(agent.metadata, "jido.topology"))
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp stop_agent(jido, pid) do
    :erpc.call(node(pid), Jido, :stop_agent, [jido, pid], 5_000)
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
