defmodule Jido.Examples.Topology.Runtime do
  @moduledoc "Public runtime inspection helpers for the topology examples."

  alias Jido.AgentServer

  def start(instance, definition, expected_resident_count) do
    id = "topology-#{System.unique_integer([:positive])}"

    with {:ok, root} <- Jido.start_agent(instance, definition, id: id),
         :ok <- AgentServer.await_ready(root),
         true <- eventually(fn -> Jido.resident_agent_count(instance) == expected_resident_count end) do
      {:ok, root}
    else
      false -> {:error, :topology_not_ready}
      error -> error
    end
  end

  def residents(instance) do
    case Jido.list_agents(instance) do
      values when is_list(values) -> values
      {:error, _reason} -> []
    end
  end

  def members(instance, root) do
    for {_id, pid} <- residents(instance), pid != root, do: pid
  end

  def labeled(instance, root, label) do
    Enum.filter(members(instance, root), fn pid ->
      case AgentServer.snapshot(pid) do
        %{agent: %{state: %{label: ^label}}} -> true
        _other -> false
      end
    end)
  end

  def named(instance, name) do
    Enum.filter(residents(instance), fn {_id, pid} ->
      match?(%{agent: %{name: ^name}}, AgentServer.snapshot(pid))
    end)
  end

  def stop(instance, root) do
    monitors = for {_id, pid} <- residents(instance), do: {pid, Process.monitor(pid)}

    with :ok <- Jido.stop_agent(instance, root),
         true <- await_down(monitors) do
      :ok
    else
      false -> {:error, :topology_still_running}
      error -> error
    end
  end

  def eventually(fun, attempts \\ 200)
  def eventually(_fun, 0), do: false

  def eventually(fun, attempts) do
    case fun.() do
      value when value in [nil, false] ->
        receive do
        after
          10 -> eventually(fun, attempts - 1)
        end

      value ->
        value
    end
  end

  defp await_down(monitors) do
    Enum.all?(monitors, fn {pid, monitor} ->
      receive do
        {:DOWN, ^monitor, :process, ^pid, _reason} -> true
      after
        5_000 -> false
      end
    end)
  end
end
