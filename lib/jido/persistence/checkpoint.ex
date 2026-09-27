defmodule Jido.Persistence.Checkpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Checkpoint, as: AgentCheckpoint
  alias Jido.Error
  alias Jido.Persistence.Record
  alias Jido.Agent.Plugin.Spec, as: AgentSpec
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Persistence.Plugin.Spec, as: PersistenceSpec

  @doc false
  @spec dump(Agent.instance(), map(), pos_integer(), term()) :: {:ok, map()} | {:error, term()}
  def dump(%Agent{} = agent, context, record_format, reason) do
    convert_state = converter(:dump, record_format, reason)

    AgentCheckpoint.checkpoint(agent, context, fn validated, _state ->
      # Preserve the supplied complete state. Validation defaults must not hide
      # a missing Plugin-owned field from its persistence conversion.
      convert_state.(validated, agent.state)
    end)
  end

  defp converter(direction, record_format, reason) do
    fn agent, state ->
      with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(agent.plugins) do
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
          :error -> {:halt, missing_plugin_state(direction, key)}
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

  defp missing_plugin_state(:dump, key),
    do: {:error, {:invalid_checkpoint, {:missing_plugin_state, key}}}

  defp missing_plugin_state(:load, _key),
    do: {:error, {:invalid_persistence_record, :plugin_state}}

  @doc false
  def restore_agent(record, agent_module, agent_id, instance) do
    with :ok <- validate_definition_revision(record, agent_module),
         {:ok, agent} <-
           AgentCheckpoint.restore(
             agent_module,
             Record.checkpoint(record),
             restore_context(record, instance),
             converter(:load, Record.format(record), :restore)
           ),
         :ok <- validate_restored_identity(agent, agent_module, agent_id) do
      {:ok, agent}
    end
  end

  defp validate_definition_revision(record, agent_module) do
    case Record.agent_vsn(record) do
      nil ->
        :ok

      saved_vsn ->
        case current_definition_revision(agent_module) do
          ^saved_vsn ->
            :ok

          current_vsn ->
            {:error,
             Error.validation_error("Stored Agent definition revision does not match",
               kind: :config,
               subject: agent_module,
               details: %{
                 code: :definition_mismatch,
                 saved_vsn: saved_vsn,
                 current_vsn: current_vsn
               }
             )}
        end
    end
  end

  defp current_definition_revision(agent_module) do
    if Code.ensure_loaded?(agent_module) and function_exported?(agent_module, :vsn, 0),
      do: agent_module.vsn(),
      else: nil
  end

  defp validate_restored_identity(%Agent{module: module, id: id}, module, id), do: :ok

  defp validate_restored_identity(_agent, _module, _id),
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
