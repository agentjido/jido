defmodule Jido.Topology.Controller.Owner do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.Telemetry.Semantic
  alias Jido.Topology.Controller.TargetStore

  require Logger

  def start(jido, controller, topology_id) do
    Task.Supervisor.start_child(Jido.task_supervisor_name(jido), fn ->
      watch(jido, controller, topology_id)
    end)
  end

  def track(owner, pid) when is_pid(owner) and is_pid(pid), do: send(owner, {:track, pid})

  defp watch(jido, controller, topology_id) do
    ref = Process.monitor(controller)
    await_down(jido, controller, topology_id, ref, %{})
  end

  defp await_down(jido, controller, topology_id, ref, tracked) do
    receive do
      {:track, pid} when is_pid(pid) ->
        await_down(jido, controller, topology_id, ref, Map.put(tracked, pid, true))

      {:DOWN, ^ref, :process, ^controller, reason} ->
        cleanup(jido, topology_id, tracked, reason)
    end
  end

  defp cleanup(jido, topology_id, tracked, reason) do
    candidates = Enum.uniq(Map.keys(tracked) ++ local_agents(jido))

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

  defp local_agents(jido) do
    case Process.whereis(Jido.agent_supervisor_name(jido)) do
      nil ->
        []

      pool ->
        pool
        |> DynamicSupervisor.which_children()
        |> Enum.reduce([], fn
          {_, pid, _, modules}, acc when is_pid(pid) and is_list(modules) ->
            if AgentServer in modules, do: [pid | acc], else: acc

          _, acc ->
            acc
        end)
    end
  catch
    :exit, _reason -> []
  end

  defp owned?(pid, topology_id) do
    agent =
      if node(pid) == node() do
        AgentServer.agent(pid)
      else
        :erpc.call(node(pid), AgentServer, :agent, [pid], 5_000)
      end

    match?(%{id: ^topology_id}, Map.get(agent.metadata, "jido.topology"))
  rescue
    _error -> false
  catch
    _kind, _reason -> false
  end

  defp stop_agent(jido, pid) when node(pid) == node(), do: Jido.stop_agent(jido, pid)

  defp stop_agent(jido, pid) do
    :erpc.call(node(pid), Jido, :stop_agent, [jido, pid], 5_000)
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
