defmodule Jido.Pod.Mutable do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.StateOp
  alias Jido.AgentServer
  alias Jido.AgentServer.State
  alias Jido.Pod.Directive.ApplyMutation
  alias Jido.Pod.Mutation
  alias Jido.Pod.Mutation.Planner
  alias Jido.Pod.Plugin
  alias Jido.Pod.TopologyState
  alias Jido.Signal

  @mutation_lock_table :jido_pod_mutation_locks
  @pod_state_key Plugin.state_key_atom()

  @spec mutate(AgentServer.server(), [Mutation.t() | term()], keyword()) ::
          {:ok, Jido.Pod.mutation_report()} | {:error, Jido.Pod.mutation_report() | term()}
  def mutate(server, ops, opts \\ []) when is_list(opts) do
    signal =
      Signal.new!(
        "pod.mutate",
        %{ops: ops, opts: Map.new(opts)},
        source: "/jido/pod/mutate"
      )

    await_timeout =
      Keyword.get(opts, :await_timeout, Keyword.get(opts, :timeout, :timer.seconds(30)))

    with {:ok, lock} <- acquire_external_mutation_lock(server) do
      with {:ok, state} <- AgentServer.state(server),
           {:ok, synced_lock} <- sync_external_mutation_lock(lock, server, state) do
        with {:ok, pod_state} <- TopologyState.fetch_state(state),
             :ok <- ensure_mutation_idle(pod_state),
             {:ok, _agent} <- AgentServer.call(server, signal) do
          await_mutation(server, await_timeout, synced_lock)
        else
          {:error, _reason} = error ->
            release_external_mutation_lock(synced_lock)
            error
        end
      else
        {:error, _reason} = error ->
          release_external_mutation_lock(lock)
          error
      end
    end
  end

  @spec mutation_effects(Agent.t(), [Mutation.t() | term()], keyword()) ::
          {:ok, [struct()]} | {:error, term()}
  def mutation_effects(%Agent{} = agent, ops, opts \\ []) when is_list(opts) do
    with {:ok, pod_state} <- TopologyState.fetch_state(agent),
         :ok <- ensure_mutation_idle(pod_state),
         {:ok, topology} <- TopologyState.fetch_topology(agent),
         {:ok, plan} <- Planner.plan(topology, ops) do
      mutation_state = %{id: plan.mutation_id, status: :running, report: plan.report, error: nil}

      {:ok,
       [
         StateOp.set_path([@pod_state_key, :topology], plan.final_topology),
         StateOp.set_path([@pod_state_key, :topology_version], plan.final_topology.version),
         StateOp.set_path([@pod_state_key, :mutation], mutation_state),
         ApplyMutation.new!(plan, opts)
       ]}
    end
  end

  @spec mark_mutation_lock(Agent.t(), map(), String.t() | nil) :: :ok
  def mark_mutation_lock(%Agent{id: id, state: state}, context, mutation_id)
      when is_map(context) do
    ensure_mutation_lock_table!()

    agent_server_pid = Map.get(context, :agent_server_pid)
    partition = Map.get(state, :__partition__)

    :ets.insert(@mutation_lock_table, {{:id, partition, id}, mutation_id || true})

    if is_pid(agent_server_pid) do
      :ets.insert(@mutation_lock_table, {{:pid, agent_server_pid}, mutation_id || true})
    end

    :ok
  end

  @spec clear_mutation_lock(State.t()) :: :ok
  def clear_mutation_lock(%State{id: id, partition: partition}) do
    ensure_mutation_lock_table!()
    :ets.delete(@mutation_lock_table, {:id, partition, id})
    :ets.delete(@mutation_lock_table, {:pid, self()})
    :ok
  end

  defp ensure_mutation_idle(%{mutation: %{status: status}})
       when status in [:running, :queued] do
    {:error, :mutation_in_progress}
  end

  defp ensure_mutation_idle(_pod_state), do: :ok

  defp await_mutation(server, await_timeout, lock) do
    case AgentServer.await_completion(
           server,
           timeout: await_timeout,
           status_path: [@pod_state_key, :mutation, :status],
           result_path: [@pod_state_key, :mutation, :report],
           error_path: [@pod_state_key, :mutation, :error]
         ) do
      {:ok, %{status: :completed, result: result}} ->
        {:ok, result}

      {:ok, %{status: :failed, result: result}} ->
        {:error, result}

      {:error, :not_found} = error ->
        release_external_mutation_lock(lock)
        error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp acquire_external_mutation_lock(server) do
    ensure_mutation_lock_table!()

    keys = external_mutation_lock_keys(server)

    if insert_lock_keys(keys) do
      {:ok, %{keys: keys}}
    else
      {:error, :mutation_in_progress}
    end
  end

  defp external_mutation_lock_keys(server) do
    case server do
      pid when is_pid(pid) -> [{:pid, pid}]
      _other -> []
    end
  end

  defp sync_external_mutation_lock(%{keys: keys} = lock, server, %State{} = state) do
    missing_keys =
      canonical_external_mutation_lock_keys(server, state)
      |> Enum.reject(&(&1 in keys))

    case acquire_missing_lock_keys(missing_keys, []) do
      {:ok, acquired_keys} ->
        {:ok, %{lock | keys: Enum.uniq(keys ++ acquired_keys)}}

      {:error, acquired_keys} ->
        release_external_mutation_lock(%{keys: keys ++ acquired_keys})
        {:error, :mutation_in_progress}
    end
  end

  defp canonical_external_mutation_lock_keys(server, %State{
         id: id,
         jido: jido,
         partition: partition
       }) do
    pid_key =
      case server do
        pid when is_pid(pid) ->
          {:pid, pid}

        id_value when is_binary(id_value) and is_atom(jido) ->
          case Jido.whereis(jido, id, partition: partition) do
            pid when is_pid(pid) -> {:pid, pid}
            _other -> nil
          end

        _other ->
          nil
      end

    [{:id, partition, id}, pid_key]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp acquire_missing_lock_keys([], acquired), do: {:ok, Enum.reverse(acquired)}

  defp acquire_missing_lock_keys([key | rest], acquired) do
    if :ets.insert_new(@mutation_lock_table, {key, true}) do
      acquire_missing_lock_keys(rest, [key | acquired])
    else
      {:error, Enum.reverse(acquired)}
    end
  end

  defp insert_lock_keys([]), do: true

  defp insert_lock_keys(keys) do
    Enum.all?(keys, &:ets.insert_new(@mutation_lock_table, {&1, true}))
  end

  defp release_external_mutation_lock(%{keys: keys}) do
    ensure_mutation_lock_table!()
    Enum.each(keys, &:ets.delete(@mutation_lock_table, &1))
    :ok
  end

  defp ensure_mutation_lock_table! do
    case :ets.whereis(@mutation_lock_table) do
      :undefined ->
        try do
          :ets.new(@mutation_lock_table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @mutation_lock_table
        end

      _tid ->
        @mutation_lock_table
    end
  end
end
