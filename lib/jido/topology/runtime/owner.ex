defmodule Jido.Topology.Runtime.Owner do
  @moduledoc false
  alias Jido.Topology.{Controller, Runtime}

  # The watcher lives in Jido, outside the replaceable runtime. A killed
  # supervisor cannot wait for descendant shutdown before OTP restarts it.
  def await_previous(jido, id) do
    case Runtime.lookup(jido, id, :runtime_owner) do
      nil -> :ok
      pid -> await(pid)
    end
  end

  defp await(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      5_000 ->
        Process.demonitor(ref, [:flush])
        {:error, :runtime_cleanup_pending}
    end
  end

  def start(jido, id, runtime) do
    caller = self()
    token = make_ref()

    with {:ok, pid} <-
           Task.Supervisor.start_child(Jido.task_supervisor_name(jido), fn ->
             {:via, Registry, {registry, key}} = Controller.name(jido, id, :runtime_owner)
             {:ok, _} = Registry.register(registry, key, nil)
             monitor = Process.monitor(runtime)
             send(caller, {token, :ready})
             watch(runtime, monitor, [])
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
          {:error, :runtime_owner_timeout}
      end
    end
  end

  def track(owner, pid), do: send(owner, {:track, pid})

  defp watch(runtime, monitor, children) do
    receive do
      {:track, pid} -> watch(runtime, monitor, [pid | children])
      {:DOWN, ^monitor, :process, ^runtime, _} -> Enum.each(children, &await_child/1)
    end
  end

  defp await_child(pid) do
    ref = Process.monitor(pid)
    receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
  end
end
