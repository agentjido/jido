defmodule Jido.AgentServer.Upgrade do
  @moduledoc false

  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.Storage

  alias Jido.Agent
  alias Jido.AgentServer.State
  alias Jido.Error

  def prepare(%State{} = data, target_module, migration) do
    with :ok <- definition_upgrade_supported?(data, target_module),
         {:ok, state} <- invoke_state_migration(migration, data.agent),
         {:ok, target} <- Agent.instantiate(target_module, id: data.agent.id, state: state),
         {:ok, plugin_specs} <- Jido.Plugin.Normalizer.normalize_all(target.plugins),
         :ok <- unchanged_plugin_contract(data.plugin_specs, plugin_specs) do
      {:ok, target, plugin_specs}
    end
  end

  def operation(operation) do
    case operation.() do
      :ok -> :ok
      {:error, _reason} = error -> error
      result -> {:error, {:invalid_upgrade_result, result}}
    end
  rescue
    error ->
      {:error,
       Error.execution_error("Agent upgrade operation failed",
         details: %{code: :agent_upgrade_failed, reason: error}
       )}
  catch
    kind, reason ->
      {:error,
       Error.execution_error("Agent upgrade operation failed",
         details: %{code: :agent_upgrade_failed, kind: kind, reason: reason}
       )}
  end

  defp definition_upgrade_supported?(%State{persistence: nil}, _target_module), do: :ok

  defp definition_upgrade_supported?(%State{agent: %{module: module}}, module), do: :ok

  defp definition_upgrade_supported?(%State{jido: jido}, _target_module) do
    if is_binary(Jido.namespace(jido)) do
      :ok
    else
      {:error, :stable_namespace_required}
    end
  end

  defp invoke_state_migration(migration, agent) do
    case migration.(agent) do
      {:ok, state} when is_map(state) and not is_struct(state) -> {:ok, state}
      {:ok, state} -> {:error, {:invalid_migrated_state, state}}
      {:error, _reason} = error -> error
      result -> {:error, {:invalid_migration_result, result}}
    end
  rescue
    error ->
      {:error,
       Error.execution_error("Agent state migration failed",
         details: %{code: :agent_state_migration_failed, reason: error}
       )}
  catch
    kind, reason ->
      {:error,
       Error.execution_error("Agent state migration failed",
         details: %{code: :agent_state_migration_failed, kind: kind, reason: reason}
       )}
  end

  defp unchanged_plugin_contract(specs, specs), do: :ok
  defp unchanged_plugin_contract(_current, _target), do: {:error, :plugin_contract_changed}

  def upgrade_definition(from, target_module, migration, %State{} = data) do
    with {:ok, target, plugin_specs} <- prepare(data, target_module, migration) do
      version = data.state_version + 1

      case Storage.persist_definition_upgrade(data, target, version) do
        :ok ->
          next_data = %{
            data
            | agent: target,
              plugin_specs: plugin_specs,
              state_version: version
          }

          {:keep_state, Idle.maybe_start_idle_timer(next_data, :idle),
           [{:reply, from, {:ok, target}}]}

        {:error, reason} ->
          error = {:persistence_failed, reason}

          {:stop_and_reply, {:shutdown, error}, [{:reply, from, {:error, error}}], data}
      end
    else
      {:error, _reason} = error ->
        {:keep_state, Idle.maybe_start_idle_timer(data, :idle), [{:reply, from, error}]}
    end
  end
end
