defmodule Jido.AgentServer.Upgrade do
  @moduledoc false

  alias Jido.Agent
  alias Jido.AgentServer.{RuntimeCheckpoint, State}
  alias Jido.Error
  alias Jido.Plugin

  @type definition_result ::
          {:ok, Agent.t(), [Jido.Plugin.Spec.t()], non_neg_integer()}
          | {:error, term()}
          | {:stop, term()}

  @doc false
  @spec operation((-> :ok | {:error, term()})) :: :ok | {:error, term()}
  def operation(operation) when is_function(operation, 0) do
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

  @doc false
  @spec definition(State.t(), module(), (Agent.t() -> {:ok, map()} | {:error, term()})) ::
          definition_result()
  def definition(%State{} = data, target_module, migration)
      when is_atom(target_module) and is_function(migration, 1) do
    with :ok <- supported?(data, target_module),
         {:ok, state} <- migrate(migration, data.agent),
         {:ok, target} <- Agent.instantiate(target_module, id: data.agent.id, state: state),
         {:ok, plugin_specs} <- Plugin.normalize_all(target.plugins),
         :ok <- unchanged_plugin_contract(data.plugin_specs, plugin_specs) do
      version = data.state_version + 1

      case persist(data, target, version) do
        :ok -> {:ok, target, plugin_specs, version}
        {:error, reason} -> {:stop, {:persistence_failed, reason}}
      end
    end
  end

  defp supported?(%State{persistence: nil}, _target_module), do: :ok
  defp supported?(%State{agent: %{module: module}}, module), do: :ok

  defp supported?(%State{jido: jido}, _target_module) do
    if is_binary(Jido.namespace(jido)) do
      :ok
    else
      {:error, :stable_namespace_required}
    end
  end

  defp migrate(migration, agent) do
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

  defp persist(%State{persistence: nil} = data, target, version) do
    RuntimeCheckpoint.put_upgrade(data, target, version)
  end

  defp persist(%State{agent: %{module: module}} = data, target, version)
       when target.module == module do
    opts = persistence_opts(data, version)
    Jido.Persistence.save_agent(data.persistence, target, opts)
  end

  defp persist(%State{} = data, target, version) do
    opts = persistence_opts(data, version)
    Jido.Persistence.replace_agent(data.persistence, data.agent, target, opts)
  end

  defp persistence_opts(data, version) do
    [
      instance: data.jido,
      namespace: data.agent_namespace,
      partition: data.partition,
      revision: version,
      expected_revision: data.state_version,
      reason: :definition_upgrade
    ]
  end
end
