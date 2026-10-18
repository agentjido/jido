defmodule Jido.AgentServer.Supervisor do
  @moduledoc """
  The OTP root for an AgentServer and its private resources.

  `start_link/1` returns `{:ok, supervisor}`. `worker/1` returns the request
  endpoint. Use `AgentServer.child_spec/1` in an application supervisor.
  Required Plugin roots and the server recover together with `:one_for_all`.
  A Plugin supervisor controls recovery inside its own tree.
  """
  use Supervisor
  alias Jido.AgentServer, as: Server
  alias Runic.Runner

  def start_link(opts, parent \\ nil) do
    with {:ok, opts} <- Server.activation_options(opts) do
      Supervisor.start_link(__MODULE__, {opts, parent}) |> finish_start(parent)
    end
  end

  defp finish_start({:ok, root} = result, parent) do
    case record_child(parent, root) do
      :ok ->
        result

      error ->
        Supervisor.stop(root)
        error
    end
  end

  defp finish_start(error, _parent), do: error

  @impl true
  def init({opts, parent}) do
    state = :ets.new(__MODULE__, [:set, :public])
    :ets.insert(state, [{:parent, parent}, {:checkpoint, opts[:agent], 0}])
    opts = Keyword.put(opts, :activation_state, state)

    children = [
      %{
        id: Server,
        start: {__MODULE__, :start_worker, [opts, self()]},
        restart: :transient,
        significant: true,
        shutdown: 10_000
      }
    ]

    Supervisor.init(children,
      strategy: :one_for_all,
      auto_shutdown: :any_significant,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  # The checkpoint is the canonical Agent and revision, not a serialized
  # runtime map. Local state rules apply; portable save/export is separate.
  @doc false
  def start_worker(opts, activation) do
    state = Keyword.fetch!(opts, :activation_state)
    # The recovery group has stopped its owned DynamicSupervisor. Its children
    # are not checkpoints; keep only independent relationships across recovery.
    :ets.match_delete(state, {{:child, :_}, %{placement: :owned}})

    checkpoint =
      if opts[:persistence] in [nil, false],
        do: restore_checkpoint(state, opts[:agent]),
        else: {:ok, opts[:agent], 0}

    with {:ok, agent, revision} <- checkpoint,
         opts = Keyword.merge(opts, agent: agent, state_version: revision),
         {:ok, pid} <- Server.start_worker(opts, activation) do
      :ets.insert(state, {:worker, pid})
      {:ok, pid}
    end
  end

  defp restore_checkpoint(state, initial) do
    with [{:checkpoint, agent, revision}] <- :ets.lookup(state, :checkpoint),
         true <- is_integer(revision) and revision >= 0,
         {:ok, agent} <- Jido.Agent.Validation.validate_instance(agent),
         true <- agent.id == initial.id,
         true <- agent.module == initial.module do
      {:ok, agent, revision}
    else
      _ -> {:error, :invalid_local_checkpoint}
    end
  end

  @doc false
  def publish_checkpoint(nil, _agent, _revision), do: :ok

  def publish_checkpoint(state, agent, revision) do
    match_spec = [
      {{:checkpoint, :_, revision - 1}, [], [{:const, {:checkpoint, agent, revision}}]}
    ]

    case :ets.select_replace(state, match_spec) do
      1 -> :ok
      0 -> {:error, :checkpoint_conflict}
    end
  rescue
    ArgumentError -> {:error, :checkpoint_unavailable}
  end

  @doc false
  def persistence_mode(state, requested) do
    if :ets.insert_new(state, {:durable_started, true}), do: requested, else: :restore
  end

  @doc false
  def restore_durable(state, agent, revision),
    do: :ets.insert(state, {:checkpoint, agent, revision})

  @doc false
  def start_plugin(spec, state) do
    [{:worker, owner}] = :ets.lookup(state, :worker)

    case :gen_statem.call(owner, {:plugin_start, spec.module}) do
      {:ok, init, current_spec} ->
        {:ok, %{start: {module, function, args}}} =
          Jido.AgentServer.Plugin.Callbacks.child_spec(init, current_spec)

        apply(module, function, args)

      {:error, :plugin_not_found} ->
        :ignore
    end
  end

  def worker(activation) do
    case List.keyfind(Supervisor.which_children(activation), Server, 0) do
      {Server, pid, :worker, _} when is_pid(pid) -> pid
      _ -> nil
    end
  end

  def start_plugin(activation, spec, child_spec, state) do
    child_spec = %{
      child_spec
      | id: {:plugin, spec.module},
        start: {__MODULE__, :start_plugin, [spec, state]}
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

  def execution(nil), do: nil
  def execution(state), do: :ets.lookup(state, :execution) |> List.first()

  def remember_execution(nil, _runner, _id, _worker), do: :ok

  def remember_execution(state, runner, id, worker) do
    case Registry.lookup(Module.concat(runner, Registry), {Runic.TaskScope, worker}) do
      [{scope, _}] ->
        :ets.insert(state, {:execution, runner, id, scope})
        :ok

      [] ->
        {:error, :ownership_scope_unavailable}
    end
  end

  def forget_execution(nil), do: :ok
  def forget_execution(state), do: :ets.delete(state, :execution)

  def close_execution(state) do
    case execution(state) do
      nil ->
        :ok

      {:execution, runner, id, scope} = execution ->
        # Owner DOWN and supervisor recovery have separate recipients. Keep
        # admission closed until the old scope has stopped its native work,
        # even when its Worker has already left the Runner registry.
        result =
          case Runner.lookup(runner, id) do
            nil -> Runic.TaskScope.close(scope)
            _worker -> Runner.cancel(runner, id)
          end

        if result == :ok, do: :ets.delete_object(state, execution)
        result
    end
  end

  def parent(state), do: :ets.lookup_element(state, :parent, 2)

  def records(state), do: :ets.match_object(state, {{:child, :_}, :_})

  def reserve(state, tag, token, caller) do
    case :ets.lookup(state, {:child, tag}) do
      [] -> :ok
      [{_, %{root: _root}}] -> throw(:tag_in_use)
      [{_, %{caller: owner}}] -> if Process.alive?(owner), do: throw(:tag_in_use)
    end

    :ets.insert(state, {{:child, tag}, %{token: token, caller: caller}})
    :ok
  catch
    :tag_in_use -> {:error, :tag_in_use}
  end

  def release(state, tag, token) do
    case :ets.lookup(state, {:child, tag}) do
      [{_, %{token: ^token}}] ->
        :ets.delete(state, {:child, tag})
        [{:worker, owner}] = :ets.lookup(state, :worker)
        send(owner, {:child_released, tag, token})

      _ ->
        :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  def record_child(parent, root, restart? \\ true)
  def record_child(nil, _root, _restart?), do: :ok

  def record_child(parent, root, restart?) do
    key = {:child, parent.tag}
    restart = Map.get(parent, :restart, :transient)

    record = %{
      token: parent.token,
      root: root,
      restart?: restart? and restart != :temporary,
      restart: restart,
      placement: parent.placement
    }

    match_spec = [{{key, %{token: parent.token}}, [], [{:const, {key, record}}]}]

    case :ets.select_replace(parent.state, match_spec) do
      1 ->
        [{:worker, owner}] = :ets.lookup(parent.state, :worker)
        send(owner, {:child_registered, parent.tag, parent.token, root})
        :ok

      0 ->
        {:error, :parent_changed}
    end
  rescue
    ArgumentError ->
      if Process.alive?(parent.activation), do: {:error, :parent_changed}, else: :ok
  end

  def child_supervisor(activation) do
    spec = %{
      id: :owned_agents,
      start: {DynamicSupervisor, :start_link, [[strategy: :one_for_one]]},
      type: :supervisor
    }

    case Supervisor.start_child(activation, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end
end
