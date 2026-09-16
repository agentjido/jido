defmodule Jido.Persistence.Checkpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Error
  alias Jido.Persistence.Record
  alias Jido.Agent.Plugin.Spec, as: AgentSpec
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Persistence.Plugin.Spec, as: PersistenceSpec
  alias Jido.Plugin

  @custom_checkpoint_kind :agent_custom

  @doc false
  @spec dump(Agent.instance(), map(), pos_integer(), term()) :: {:ok, map()} | {:error, term()}
  def dump(%Agent{} = agent, context, record_format, reason) do
    with {:ok, checkpoint} <- Agent.checkpoint(agent, context),
         {:ok, checkpoint} <- dump_plugin_state(agent, checkpoint, record_format, reason) do
      {:ok, checkpoint}
    end
  end

  @doc false
  @spec load(module(), map(), pos_integer(), term()) :: {:ok, map()} | {:error, term()}
  def load(agent_module, checkpoint, record_format, reason)
      when is_atom(agent_module) and is_map(checkpoint) do
    if custom_checkpoint?(checkpoint) do
      {:ok, checkpoint}
    else
      with {:ok, declarations} <- plugin_declarations(agent_module, checkpoint),
           {:ok, specs} <- Plugin.normalize_all(declarations),
           {:ok, state} <-
             load_owned_state(Map.get(checkpoint, :state), specs, record_format, reason) do
        {:ok, Map.put(checkpoint, :state, state)}
      end
    end
  end

  defp dump_plugin_state(agent, checkpoint, record_format, reason) do
    if custom_checkpoint?(checkpoint) do
      {:ok, checkpoint}
    else
      with {:ok, specs} <- Plugin.normalize_all(agent.plugins),
           {:ok, state} <- dump_owned_state(agent.state, specs, record_format, reason) do
        {:ok, Map.put(checkpoint, :state, state)}
      end
    end
  end

  defp dump_owned_state(state, specs, record_format, reason) when is_map(state) do
    convert_owned_state(state, specs, :dump, record_format, reason)
  end

  defp load_owned_state(state, specs, record_format, reason) when is_map(state) do
    convert_owned_state(state, specs, :load, record_format, reason)
  end

  defp load_owned_state(_state, _specs, _record_format, _reason),
    do: {:error, {:invalid_persistence_record, :checkpoint}}

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

  defp plugin_declarations(agent_module, checkpoint) do
    cond do
      generated_agent_module?(agent_module) ->
        case agent_module.definition() do
          %Agent{} = definition -> {:ok, definition.plugins}
          _value -> {:error, {:invalid_persistence_record, :agent_definition}}
        end

      match?(%Agent{}, Map.get(checkpoint, :definition)) ->
        {:ok, Map.fetch!(checkpoint, :definition).plugins}

      true ->
        {:ok, []}
    end
  rescue
    _error -> {:error, {:invalid_persistence_record, :agent_definition}}
  catch
    _kind, _reason -> {:error, {:invalid_persistence_record, :agent_definition}}
  end

  defp generated_agent_module?(module) do
    module != Agent and Code.ensure_loaded?(module) and
      function_exported?(module, :definition, 0)
  end

  defp custom_checkpoint?(checkpoint), do: Map.get(checkpoint, :kind) == @custom_checkpoint_kind

  @doc false
  def restore_agent(record, agent_module, agent_id, instance) do
    with :ok <- validate_definition_revision(record, agent_module),
         {:ok, checkpoint} <- restore_checkpoint(record, agent_module),
         {:ok, agent} <-
           Agent.restore(agent_module, checkpoint, restore_context(record, instance)),
         :ok <- validate_restored_identity(agent, agent_module, agent_id) do
      {:ok, agent}
    end
  end

  defp restore_checkpoint(record, agent_module) do
    checkpoint = Record.checkpoint(record)

    if Record.format(record) in [Record.format_version(), Record.ref_format_version()] do
      load(agent_module, checkpoint, Record.format(record), :restore)
    else
      {:ok, checkpoint}
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
