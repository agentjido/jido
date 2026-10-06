defmodule Jido.AgentServer.RuntimeCheckpoint do
  @moduledoc false

  # This instance-owned snapshot copies terms for local abnormal restarts.
  # It does not recreate resources, verify handle liveness, transfer port
  # ownership, or install monitors in the replacement AgentServer. Startup
  # validates the restored Agent against its live-state schema.

  alias Jido.Agent
  alias Jido.AgentServer.{Options, State}
  alias Jido.RuntimeStore

  @hive :agent_runtime_checkpoints
  @locations :agent_checkpoint_locations

  @doc false
  def prepare_definition(jido, %Agent{} = source, %Agent{} = candidate, policy, opts)
      when policy in [:preserve, :reset] do
    partition = Keyword.get(opts, :partition)

    with :ok <- preparation_agents(source, candidate) do
      case fetch(jido, key(candidate.id, partition)) do
        {:ok, %{agent: %Agent{} = saved, state_version: revision}}
        when is_integer(revision) and revision >= 0 ->
          prepare_loaded(jido, source, saved, candidate, revision, policy, opts)

        :error ->
          prepare_missing(jido, source, candidate, policy, opts)

        {:error, :not_running} ->
          {:error, :runtime_checkpoint_unavailable}

        {:error, :timeout} ->
          {:error, :runtime_checkpoint_unavailable}

        {:ok, _invalid} ->
          {:error, :invalid_runtime_checkpoint}
      end
    end
  end

  def prepare_definition(_jido, _source, _candidate, policy, _opts),
    do: {:error, {:unsupported_definition_policy, policy}}

  @doc false
  @spec restore(Options.t()) ::
          {:ok, Agent.t(), non_neg_integer()} | {:error, term()}
  def restore(%Options{agent: %Agent{}} = options) do
    with {:ok, agent, version, _status} <- restore_with_status(options),
         do: {:ok, agent, version}
  end

  @doc false
  @spec restore_with_status(Options.t()) ::
          {:ok, Agent.t(), non_neg_integer(), :none | :restored} | {:error, term()}
  def restore_with_status(%Options{agent: %Agent{} = initial} = options) do
    case fetch(options.jido, key(initial.id, options.partition)) do
      {:ok, %{agent: %Agent{} = agent, state_version: version}}
      when agent.id == initial.id and agent.module == initial.module and
             is_integer(version) and version >= 0 ->
        {:ok, agent, version, :restored}

      {:ok,
       %{
         agent: %Agent{} = agent,
         state_version: version,
         upgrade_from_module: source_module
       }}
      when agent.id == initial.id and source_module == initial.module and
             is_integer(version) and version >= 0 ->
        {:ok, agent, version, :restored}

      :error ->
        {:ok, initial, options.state_version, :none}

      {:error, :not_running} ->
        {:error, :runtime_checkpoint_unavailable}

      {:error, :timeout} ->
        {:error, :runtime_checkpoint_unavailable}

      {:ok, _invalid} ->
        {:error, :invalid_runtime_checkpoint}
    end
  end

  @doc false
  @spec put(State.t(), Agent.t(), non_neg_integer()) :: :ok | {:error, term()}
  def put(%State{jido: jido, partition: partition} = data, %Agent{} = agent, state_version)
      when is_atom(jido) and not is_nil(jido) do
    with {:ok, owner} <- owner_key(jido, Map.get(data.config, :checkpoint_owner)),
         :ok <- track_location(jido, owner) do
      RuntimeStore.put(jido, @hive, key(agent.id, partition), %{
        agent: agent,
        state_version: state_version,
        upgrade_from_module: data.checkpoint_origin_module || data.agent.module,
        owner: owner
      })
    end
  end

  def put(%State{}, %Agent{}, _state_version), do: :ok

  @doc false
  @spec delete(State.t()) :: :ok | {:error, term()}
  def delete(%State{jido: jido, agent: agent, partition: partition})
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.delete(jido, @hive, key(agent.id, partition))
  end

  def delete(%State{}), do: :ok

  # Registered owners retain one stable scope across process replacement.
  # The owner clears the complete scope after its final clean shutdown.
  @doc false
  def delete_owned(jido, keys) do
    with {:ok, entries} <- RuntimeStore.fetch_all(jido, @locations) do
      locations = for {{key, target}, _} <- entries, key in keys, do: target

      errors =
        Enum.flat_map(Enum.uniq([node() | locations]), fn target ->
          case on_node(target, __MODULE__, :delete_local_owned, [jido, node(), keys]) do
            :ok ->
              Enum.each(keys, &RuntimeStore.delete(jido, @locations, {&1, target}))
              []

            {:error, reason} ->
              [{target, reason}]
          end
        end)

      if errors == [], do: :ok, else: {:error, errors}
    end
  end

  @doc false
  def delete_local_owned(jido, owner_node, keys) do
    with {:ok, entries} <- RuntimeStore.fetch_all(jido, @hive) do
      Enum.reduce_while(entries, :ok, fn {key, record}, :ok ->
        result =
          case record do
            %{owner: {^owner_node, owner_key}} ->
              if owner_key in keys, do: RuntimeStore.delete(jido, @hive, key), else: :ok

            _ ->
              :ok
          end

        if result == :ok, do: {:cont, :ok}, else: {:halt, result}
      end)
    end
  end

  defp owner_key(_jido, nil), do: {:ok, nil}

  defp owner_key(jido, owner) do
    case on_node(node(owner), Registry, :keys, [Jido.registry_name(jido), owner]) do
      [key] -> registered_owner(jido, owner, key)
      {:error, _} = error -> error
      _ -> {:ok, owner}
    end
  end

  defp registered_owner(jido, owner, key) do
    case on_node(node(owner), Registry, :lookup, [Jido.registry_name(jido), key]) do
      [{^owner, {:checkpoint_owner, scope}}] -> {:ok, {node(owner), scope}}
      {:error, _} = error -> error
      _ -> {:ok, {node(owner), key}}
    end
  end

  defp track_location(jido, {owner_node, key}) when owner_node != node(),
    do: on_node(owner_node, RuntimeStore, :put, [jido, @locations, {key, node()}, true])

  defp track_location(_jido, _owner), do: :ok

  defp preparation_agents(
         %Agent{id: nil, state: nil, module: module},
         %Agent{id: id, state: state, module: module}
       )
       when is_binary(id) and is_map(state) and not is_struct(state),
       do: :ok

  defp preparation_agents(%Agent{module: source}, %Agent{module: candidate})
       when source != candidate,
       do: {:error, {:agent_module_mismatch, source, candidate}}

  defp preparation_agents(_source, _candidate),
    do: {:error, :invalid_definition_preparation_agents}

  defp prepare_loaded(_jido, _source, saved, candidate, _revision, :preserve, _opts) do
    validate_preserved_state(saved, candidate)
  end

  defp prepare_loaded(_jido, _source, candidate, candidate, _revision, :reset, _opts), do: :ok

  defp prepare_loaded(jido, source, saved, candidate, revision, :reset, opts) do
    with :ok <- saved_identity(saved, source, candidate),
         do: put_prepared(jido, source, candidate, revision + 1, opts)
  end

  defp prepare_missing(_jido, _source, _candidate, :preserve, _opts), do: :ok

  defp prepare_missing(jido, source, candidate, :reset, opts),
    do: put_prepared(jido, source, candidate, 0, opts)

  defp put_prepared(jido, source, candidate, revision, opts) do
    partition = Keyword.get(opts, :partition)

    with {:ok, owner} <- owner_key(jido, Keyword.get(opts, :checkpoint_owner)),
         :ok <- track_location(jido, owner) do
      RuntimeStore.put(jido, @hive, key(candidate.id, partition), %{
        agent: candidate,
        state_version: revision,
        upgrade_from_module: source.module,
        owner: owner
      })
    end
  end

  defp validate_preserved_state(saved, candidate) do
    with :ok <- saved_identity(saved, Jido.Agent.definition(candidate), candidate),
         {:ok, _validated} <- Agent.validate_instance(%{candidate | state: saved.state}),
         do: :ok
  end

  defp saved_identity(
         %Agent{id: id, module: module},
         %Agent{module: module},
         %Agent{id: id, module: module}
       ),
       do: :ok

  defp saved_identity(_saved, _source, _candidate),
    do: {:error, :saved_agent_identity_mismatch}

  defp on_node(target, module, function, args) when target == node(),
    do: apply(module, function, args)

  defp on_node(target, module, function, args) do
    :erpc.call(target, module, function, args, 5_000)
  catch
    kind, reason -> {:error, {:checkpoint_owner_unavailable, kind, reason}}
  end

  defp fetch(jido, key) when is_atom(jido) and not is_nil(jido),
    do: RuntimeStore.fetch(jido, @hive, key)

  defp fetch(_jido, _key), do: :error

  defp key(agent_id, partition), do: Jido.partition_key(agent_id, partition)
end
