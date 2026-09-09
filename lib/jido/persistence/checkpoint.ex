defmodule Jido.Persistence.Checkpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Plugin.Spec, as: AgentSpec
  alias Jido.Persistence.Plugin, as: PersistencePlugin
  alias Jido.Persistence.Plugin.Spec, as: PersistenceSpec
  alias Jido.Plugin

  @custom_checkpoint_kind :agent_custom

  @doc false
  @spec dump(Agent.t(), map(), pos_integer(), term()) :: {:ok, map()} | {:error, term()}
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
    Enum.reduce_while(specs, {:ok, state}, fn
      %{agent: %AgentSpec{state_key: key}, persistence: %PersistenceSpec{}} = spec,
      {:ok, current} ->
        context = PersistencePlugin.context(spec, :dump, record_format, reason)

        with {:ok, value} <- Map.fetch(current, key),
             {:ok, dumped} <- PersistencePlugin.dump(spec, value, context) do
          {:cont, {:ok, Map.put(current, key, dumped)}}
        else
          :error -> {:halt, {:error, {:invalid_checkpoint, {:missing_plugin_state, key}}}}
          {:error, _reason} = error -> {:halt, error}
        end

      _spec, result ->
        {:cont, result}
    end)
  end

  defp dump_owned_state(_state, _specs, _record_format, _reason),
    do: {:error, {:invalid_checkpoint, :state}}

  defp load_owned_state(state, specs, record_format, reason) when is_map(state) do
    Enum.reduce_while(specs, {:ok, state}, fn
      %{agent: %AgentSpec{state_key: key}, persistence: %PersistenceSpec{}} = spec,
      {:ok, current} ->
        context = PersistencePlugin.context(spec, :load, record_format, reason)

        with {:ok, value} <- Map.fetch(current, key),
             {:ok, loaded} <- PersistencePlugin.load(spec, value, context) do
          {:cont, {:ok, Map.put(current, key, loaded)}}
        else
          :error -> {:halt, {:error, {:invalid_persistence_record, :plugin_state}}}
          {:error, _reason} = error -> {:halt, error}
        end

      _spec, result ->
        {:cont, result}
    end)
  end

  defp load_owned_state(_state, _specs, _record_format, _reason),
    do: {:error, {:invalid_persistence_record, :checkpoint}}

  defp plugin_declarations(agent_module, checkpoint) do
    cond do
      generated_agent_module?(agent_module) ->
        case agent_module.agent() do
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
    module != Agent and Code.ensure_loaded?(module) and function_exported?(module, :agent, 0)
  end

  defp custom_checkpoint?(checkpoint), do: Map.get(checkpoint, :kind) == @custom_checkpoint_kind
end
