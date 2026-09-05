defmodule Jido.AgentServer.ChildPlacement do
  @moduledoc false

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive
  alias Jido.AgentServer.SpawnRegistry

  # The target Registry and the parent activation's spawn_ref identify one
  # request. Repeated calls cannot attach an unrelated Agent with the same id.
  def start(target, jido, opts, restart, timeout) do
    remote_call(target, :start_local, [jido, opts, restart], timeout)
  end

  def start_local(jido, opts, restart) do
    with :ok <- Directive.validate_agent_target(Keyword.fetch!(opts, :agent)) do
      spec =
        Supervisor.child_spec({Server, opts},
          start: {__MODULE__, :start_link, [opts]},
          restart: restart
        )

      case DynamicSupervisor.start_child(Jido.agent_supervisor_name(jido), spec) do
        {:error, {:already_started, pid}} ->
          with {:ok, ^pid} <- resolve_existing(pid, opts),
               {:ok, info} <- Server.creation_info(pid),
               do: {:ok, pid, info}

        {:ok, pid} ->
          with {:ok, info} <- Server.creation_info(pid), do: {:ok, pid, info}

        {:ok, pid, _info} ->
          with {:ok, info} <- Server.creation_info(pid), do: {:ok, pid, info}

        :ignore ->
          {:error, :spawn_request_closed}

        result ->
          result
      end
    end
  catch
    :exit, {:noproc, _} -> {:error, :jido_instance_not_running}
  end

  # Also used by the target supervisor on restart. A permanent child must not
  # restart forever after the parent activation has stopped or disconnected.
  def start_link(opts) do
    parent = Keyword.fetch!(opts, :parent)
    jido = Keyword.fetch!(opts, :jido)

    if alive?(parent.pid) or Keyword.get(opts, :on_parent_death, :stop) != :stop do
      case SpawnRegistry.claim(jido, parent) do
        :ok -> start_claimed(jido, parent, opts)
        :closed -> :ignore
        {:existing, pid} -> {:error, {:already_started, pid}}
        {:error, _} = error -> error
      end
    else
      :ignore
    end
  end

  defp start_claimed(jido, parent, opts) do
    case Server.start_link(opts) do
      {:ok, pid} ->
        try do
          case SpawnRegistry.started(jido, parent, pid) do
            :ok ->
              {:ok, pid}

            {:error, _} = error ->
              Server.stop(pid)
              error
          end
        catch
          kind, reason ->
            Server.stop(pid)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

      error ->
        :ok = SpawnRegistry.failed(jido, parent)
        error
    end
  end

  def stop(jido, pid, reason, timeout) when node(pid) == node() do
    stop_local(jido, pid, reason, timeout)
  end

  def stop(jido, pid, reason, timeout) do
    remote_call(node(pid), :stop_local, [jido, pid, reason, timeout], timeout)
  end

  def stop_local(jido, pid, reason, timeout) do
    with :ok <- retire(jido, pid) do
      stop_process(jido, pid, reason, timeout)
    end
  end

  defp retire(jido, pid) do
    SpawnRegistry.retire(jido, pid)
  catch
    :exit, reason -> {:error, {:spawn_registry_unavailable, reason}}
  end

  defp stop_process(jido, pid, reason, timeout) do
    case DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), pid) do
      :ok -> :ok
      {:error, :not_found} -> Server.stop(pid, reason, timeout)
    end
  catch
    :exit, {:noproc, _} = reason ->
      if Process.alive?(pid), do: {:error, reason}, else: :ok

    :exit, reason ->
      {:error, reason}
  end

  def alive?(pid) when is_pid(pid) and node(pid) == node(), do: Process.alive?(pid)

  def alive?(pid) when is_pid(pid) do
    :erpc.call(node(pid), Process, :alive?, [pid], 1_000)
  catch
    _kind, _reason -> false
  end

  def alive?(_pid), do: false

  defp resolve_existing(pid, opts) do
    parent = Keyword.fetch!(opts, :parent)

    case Server.status(pid) do
      %{runtime: %{parent: %{pid: owner, tag: tag, spawn_ref: request}}}
      when owner == parent.pid and tag == parent.tag and request == parent.spawn_ref ->
        {:ok, pid}

      _ ->
        {:error, {:child_identity_in_use, Keyword.fetch!(opts, :id)}}
    end
  end

  defp remote_call(target, function, args, timeout) do
    :erpc.call(target, __MODULE__, function, args, timeout)
  catch
    :error, {:erpc, reason} when reason in [:timeout, :noconnection] ->
      {:uncertain, reason}

    :error, {:erpc, reason} when reason in [:badarg, :notsup] ->
      {:error, {:remote_call_failed, target, reason}}

    kind, reason ->
      {:uncertain, {kind, reason}}
  end
end
