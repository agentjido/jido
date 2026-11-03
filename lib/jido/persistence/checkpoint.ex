defmodule Jido.Persistence.Checkpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Persistence.Record
  alias Jido.Persistence.Snapshot
  alias Jido.Agent.Plugin.Spec, as: AgentSpec
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Persistence.Plugin.Spec, as: PersistenceSpec

  @doc false
  @spec dump(Agent.instance(), map(), pos_integer(), term()) :: {:ok, map()} | {:error, term()}
  def dump(agent, context, record_format, reason) do
    dump_agent(agent, context, converter(:dump, record_format, reason))
  end

  @doc false
  @spec dump_agent(Agent.instance(), map()) :: {:ok, map()} | {:error, term()}
  def dump_agent(agent, context \\ %{}), do: dump_agent(agent, context, &keep_state/2)

  @doc false
  @spec dump_agent(Agent.instance(), map(), (Agent.instance(), map() -> {:ok, map()} | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def dump_agent(%Agent{} = agent, context, convert_state) when is_map(context),
    do: Snapshot.dump(agent, context, convert_state)

  def dump_agent(_agent, _context, _convert_state),
    do: invalid_agent_snapshot()

  @doc false
  @spec dump_default_agent(Agent.instance(), map()) :: {:ok, map()} | {:error, term()}
  def dump_default_agent(%Agent{} = agent, context) when is_map(context),
    do: Snapshot.dump(agent, context, &keep_state/2, :default)

  def dump_default_agent(_agent, _context),
    do: invalid_agent_snapshot()

  @doc false
  @spec load_agent(module(), map(), map()) :: {:ok, Agent.instance()} | {:error, term()}
  def load_agent(module, snapshot, context \\ %{}),
    do: load_agent(module, snapshot, context, &keep_state/2)

  @doc false
  @spec load_agent(module(), map(), map(), (Agent.instance(), map() -> {:ok, map()} | {:error, term()})) ::
          {:ok, Agent.instance()} | {:error, term()}
  def load_agent(module, snapshot, context, convert_state) do
    with {:ok, agent} <- Snapshot.load(snapshot, context, convert_state) do
      if agent.module == module,
        do: {:ok, agent},
        else:
          Jido.Error.validation_result(
            :snapshot_identity,
            [:agent, :module],
            "Saved Agent origin differs from the requested origin"
          )
    end
  end

  defp converter(direction, record_format, reason) do
    fn agent, state ->
      with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Jido.Agent.Plugin.declarations(agent)) do
        convert_owned_state(state, specs, direction, record_format, reason)
      end
    end
  end

  defp convert_owned_state(state, specs, direction, record_format, reason) do
    Enum.reduce_while(specs, {:ok, state}, fn
      %{agent: %AgentSpec{state_key: key}, persistence: %PersistenceSpec{}} = spec, {:ok, current} ->
        context = PersistencePlugin.context(spec, direction, record_format, reason)

        with {:ok, value} <- Map.fetch(current, key),
             {:ok, converted} <- convert_plugin_value(spec, value, context, direction) do
          {:cont, {:ok, Map.put(current, key, converted)}}
        else
          :error -> {:halt, {:error, {:invalid_persistence_record, :plugin_state}}}
          {:error, _reason} = error -> {:halt, error}
        end

      _spec, result ->
        {:cont, result}
    end)
  end

  defp convert_plugin_value(spec, value, context, :dump),
    do: PersistencePlugin.dump(spec, value, context)

  defp convert_plugin_value(spec, value, context, :load),
    do: PersistencePlugin.load(spec, value, context)

  @doc false
  def restore_agent(record, agent_module, agent_id, instance) do
    with {:ok, agent} <-
           load_agent(
             agent_module,
             Record.checkpoint(record),
             restore_context(record, instance),
             converter(:load, Record.format(record), :restore)
           ),
         :ok <- validate_restored_id(agent, agent_id),
         true <- agent.vsn == Record.agent_vsn(record) do
      {:ok, agent}
    else
      false -> {:error, {:invalid_persistence_record, :vsn}}
      error -> error
    end
  end

  @doc false
  def restore_snapshot(snapshot, context) do
    Jido.Persistence.Snapshot.load(
      snapshot,
      context,
      converter(:load, Record.format_version(), :restore)
    )
  end

  defp validate_restored_id(%Agent{id: id}, id), do: :ok

  defp validate_restored_id(_agent, _id),
    do: {:error, {:invalid_persistence_record, :checkpoint_identity}}

  defp restore_context(record, instance) do
    %{
      instance: instance,
      partition: Map.fetch!(record, :partition),
      revision: Record.revision(record),
      reason: :restore
    }
  end

  defp keep_state(_agent, state), do: {:ok, state}

  defp invalid_agent_snapshot,
    do: Jido.Error.validation_result(:invalid_snapshot, [], "Expected an Agent instance and context Map")
end
