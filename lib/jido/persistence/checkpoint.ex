defmodule Jido.Persistence.Checkpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Persistence.AgentCheckpoint
  alias Jido.Persistence.Record
  alias Jido.Agent.Plugin.Spec, as: AgentSpec
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Persistence.Plugin.Spec, as: PersistenceSpec

  @doc false
  @spec dump(Agent.instance(), map(), pos_integer(), term()) :: {:ok, map()} | {:error, term()}
  def dump(agent, context, record_format, reason) do
    AgentCheckpoint.checkpoint(agent, context, converter(:dump, record_format, reason))
  end

  defp converter(direction, record_format, reason) do
    fn agent, state ->
      with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent)) do
        convert_owned_state(state, specs, direction, record_format, reason)
      end
    end
  end

  defp convert_owned_state(state, specs, direction, record_format, reason) do
    Enum.reduce_while(specs, {:ok, state}, fn
      %{agent: %AgentSpec{state_key: key}, persistence: %PersistenceSpec{}} = spec,
      {:ok, current} ->
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
           AgentCheckpoint.restore(
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
end
