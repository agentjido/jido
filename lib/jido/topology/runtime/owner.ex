defmodule Jido.Topology.Runtime.Owner do
  @moduledoc false
  require Logger
  alias Jido.AgentServer.{RuntimeCheckpoint, Shutdown}
  alias Jido.Topology.{Child, Controller, Runtime}

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

  def start(config, runtime) do
    jido = config.jido
    id = config.id

    scope = %{
      jido: jido,
      keys: owner_keys(config.instance.definition, id, config.checkpoint_scope),
      parent_gate: config.parent_gate
    }

    caller = self()
    token = make_ref()

    with {:ok, pid} <-
           Task.Supervisor.start_child(Jido.task_supervisor_name(jido), fn ->
             {:via, Registry, {registry, key}} = Controller.name(jido, id, :runtime_owner)
             {:ok, _} = Registry.register(registry, key, {:checkpoint_owner, hd(scope.keys)})
             monitor = Process.monitor(runtime)
             send(caller, {token, :ready})
             watch(scope, runtime, monitor, [])
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

  defp watch(config, runtime, monitor, children) do
    receive do
      {:track, pid} ->
        watch(config, runtime, monitor, [pid | children])

      {:DOWN, ^monitor, :process, ^runtime, reason} ->
        Enum.each(children, &await_child/1)
        registry = Jido.registry_name(config.jido)

        for {_, key} = scope <- tl(config.keys),
            {pid, {:checkpoint_owner, ^scope}} <- Registry.lookup(registry, key),
            do: await_child(pid)

        if Shutdown.clean?(reason) and live_parent_gate?(config.parent_gate) do
          case RuntimeCheckpoint.delete_owned(config.jido, config.keys) do
            :ok ->
              :ok

            {:error, reason} ->
              Logger.error("Runtime checkpoint cleanup failed: #{inspect(reason)}")
          end
        end
    end
  end

  defp owner_keys(definition, id, scope) do
    [
      {scope, {:topology, id, :runtime_owner}}
      | Enum.flat_map(definition.children, &owner_keys(&1.topology, Child.id(id, &1.key), scope))
    ]
  end

  defp live_parent_gate?(nil), do: true

  defp live_parent_gate?(%{name: name, supervisor: supervisor}) do
    with pid when is_pid(pid) <- GenServer.whereis(name),
         {:links, links} <- Process.info(pid, :links),
         do: supervisor in links,
         else: (_ -> false)
  end

  defp await_child(pid) do
    ref = Process.monitor(pid)
    receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
  end
end
