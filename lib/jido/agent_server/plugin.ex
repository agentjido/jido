defmodule Jido.AgentServer.Plugin do
  @moduledoc """
  Provides helpers for the Agent Server callbacks of `Jido.Plugin`.

  These callbacks can reject live commands or return one transient package-owned
  runtime input. It cannot replace pure prepared input or change the Agent,
  source Signal, or caller context. It can also prepare outbound Signals,
  declare one permanent runtime root, gate readiness, receive each Turn commit,
  and dispatch owned Directives after commit. Agent Server owns all tasks,
  limits, restart policy, and settlement. The owner wrapper hosts each root
  generation as temporary so it can restart the root with a fresh committed
  state and state version.
  """

  alias Jido.Agent.Command
  alias Jido.Agent.Error
  alias Jido.AgentServer.Plugin.{Callbacks, Commit}
  alias Jido.Plugin.{DirectiveContext, Init}

  @doc "Gets one Plugin-owned field from the current complete Agent state."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(%Init{agent_server: agent_server, module: package}, timeout \\ 5_000) do
    Jido.AgentServer.plugin_state(agent_server, package, timeout)
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end

  @doc false
  def directive_owner(specs, directive) do
    case Jido.Plugin.directive_owner(specs, directive) do
      %{agent_server: %{dispatch?: true}} = owner -> owner
      _ -> nil
    end
  end

  @doc false
  def validate_changes(specs, changed) do
    Enum.reduce_while(specs, :ok, fn spec, :ok ->
      if spec.module in changed and match?(%{runtime?: true}, spec.agent_server) and
           not function_exported?(spec.module, :quiesce, 2) do
        {:halt,
         Error.fail(
           :plugin_quiescence_required,
           [:extensions],
           "Plugin changes require quiesce and resume callbacks",
           %{plugin: spec.module}
         )}
      else
        {:cont, :ok}
      end
    end)
  end

  @doc false
  def bootstrap(data, owner) do
    Enum.reduce_while(data.plugin_specs, {:ok, %{}}, fn spec, {:ok, refs} ->
      case Callbacks.child_spec(init(data, spec, owner), spec) do
        :none ->
          {:cont, {:ok, Map.put(refs, spec.module, nil)}}

        {:ok, child_spec} ->
          case start(data.activation, spec, child_spec, data.activation_state) do
            {:ok, pid} -> {:cont, {:ok, Map.put(refs, spec.module, pid)}}
            _ -> {:halt, {:error, :plugin_start_failed}}
          end

        _ ->
          {:halt, {:error, :invalid_plugin_child_spec}}
      end
    end)
    |> case do
      {:ok, refs} -> await_ready(data.plugin_specs, refs)
      error -> error
    end
  catch
    _, _ -> {:error, :plugin_start_failed}
  end

  @doc false
  def init(data, spec, owner) do
    %Init{
      agent_server: owner,
      agent_id: data.agent.id,
      module: spec.module,
      plugin_state: owned_state(data.agent, spec),
      state_version: data.state_version,
      jido: data.jido,
      partition: data.partition
    }
  end

  @doc false
  def owned_state(agent, %{agent: %{state_key: key}}),
    do: Map.get(agent.state, key)

  def owned_state(_agent, _spec), do: nil

  @doc false
  def admit(%Command{} = command, data) do
    Callbacks.admit(
      command,
      data.plugin_specs,
      data.plugin_refs,
      data.state_version
    )
  end

  @doc false
  def pause(specs, refs, callback) do
    Enum.reduce_while(specs, :ok, fn spec, :ok ->
      result =
        bounded(fn ->
          Jido.Plugin.Error.safe_apply(
            spec.module,
            spec.module,
            callback,
            [Map.get(refs, spec.module), spec.agent_server.options],
            "Plugin configuration boundary failed"
          )
        end)

      if result == :ok,
        do: {:cont, :ok},
        else: {:halt, {:error, {callback, spec.module, result}}}
    end)
  end

  @doc false
  def rebuild(data, owner, changed) do
    with :ok <- remove_roots(data.activation, changed),
         do: bootstrap(data, owner)
  end

  @doc false
  def commit_specs(specs), do: Callbacks.commit_specs(specs)

  @doc false
  def after_commit(data, active, plugin) do
    commit = %Commit{
      plugin: plugin.module,
      turn_id: active.turn_id,
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      plugin_state: owned_state(data.agent, plugin),
      state_version: data.state_version,
      jido: data.jido,
      partition: data.partition
    }

    Callbacks.after_commit(plugin, Map.get(data.plugin_refs, plugin.module), commit)
  end

  @doc false
  def dispatch(data, active, directive) do
    case directive_owner(data.plugin_specs, directive) do
      nil ->
        :unowned

      owner ->
        context = %DirectiveContext{
          turn_id: active.turn_id,
          agent_id: data.agent.id,
          source_signal: active.source_signal,
          effective_signal: active.prepared.signal,
          state_version: data.state_version,
          plugin_state: owned_state(data.agent, owner),
          turn_context: active.turn_context,
          jido: data.jido,
          partition: data.partition
        }

        Callbacks.dispatch(
          owner,
          Map.get(data.plugin_refs, owner.module),
          directive,
          context
        )
    end
  end

  @doc false
  def start_root(spec, state) do
    [{:worker, owner}] = :ets.lookup(state, :worker)

    case :gen_statem.call(owner, {:plugin_start, spec.module}) do
      {:ok, init, current_spec} ->
        {:ok, %{start: {module, function, args}}} = Callbacks.child_spec(init, current_spec)
        apply(module, function, args)

      {:error, :plugin_not_found} ->
        :ignore
    end
  end

  @doc false
  def start(activation, spec, child_spec, state) do
    child_spec = %{
      child_spec
      | id: {:plugin, spec.module},
        start: {__MODULE__, :start_root, [spec, state]}
    }

    case Supervisor.start_child(activation, child_spec) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      {:ok, pid, _info} when is_pid(pid) ->
        {:ok, pid}

      {:error, {:already_started, pid}} = error ->
        case List.keyfind(Supervisor.which_children(activation), child_spec.id, 0) do
          {_, ^pid, _, _} when is_pid(pid) -> {:ok, pid}
          _ -> error
        end

      {:ok, _} ->
        {:error, :plugin_root_required}

      error ->
        error
    end
  end

  defp await_ready(specs, refs) do
    Enum.reduce_while(specs, {:ok, refs}, fn spec, result ->
      case Callbacks.await_ready(spec, Map.get(refs, spec.module)) do
        :ok -> {:cont, result}
        _ -> {:halt, {:error, :plugin_not_ready}}
      end
    end)
  end

  defp bounded(fun) do
    task = Task.async(fun)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :plugin_control_timeout}
    end
  end

  defp remove_roots(activation, changed) do
    Enum.reduce_while(changed, :ok, fn module, :ok ->
      case remove_root(activation, {:plugin, module}) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp remove_root(root, id) do
    case Supervisor.terminate_child(root, id) do
      :ok -> Supervisor.delete_child(root, id)
      {:error, :not_found} -> :ok
    end
  end
end
