defmodule Jido.AgentServer.Storage do
  @moduledoc false

  require Logger

  alias Jido.Agent
  alias Jido.AgentServer.{Options, RuntimeCheckpoint, Shutdown, State}

  def restore_initial_agent(%Options{restore: false, persistence: nil} = opts) do
    {:ok, opts.agent, opts.state_version, :none}
  end

  def restore_initial_agent(%Options{restore: false} = opts) do
    {:ok, opts.agent, opts.state_version, :create}
  end

  def restore_initial_agent(%Options{persistence: nil, restore: :required}) do
    {:error, :persistence_not_configured}
  end

  def restore_initial_agent(%Options{persistence: nil} = opts) do
    with {:ok, agent, version} <- RuntimeCheckpoint.restore(opts) do
      {:ok, agent, version, :none}
    end
  end

  def restore_initial_agent(%Options{} = opts) do
    load_opts = [
      instance: opts.jido,
      namespace: Jido.namespace(opts.jido),
      partition: opts.partition
    ]

    case Jido.Persistence.load_agent_with_revision(
           opts.persistence,
           opts.agent.module,
           opts.agent.id,
           load_opts
         ) do
      {:ok, agent, version} ->
        {:ok, agent, version, :restored}

      {:error, :not_found} when opts.restore == :if_found ->
        {:ok, opts.agent, opts.state_version, :create}

      {:error, _reason} = error ->
        error
    end
  end

  def persist_initial_agent(%State{initial_persistence: :create, state_version: 0} = data) do
    opts = [
      instance: data.jido,
      namespace: data.agent_namespace,
      partition: data.partition,
      revision: 0,
      reason: :activate
    ]

    case Jido.Persistence.create_agent(data.persistence, data.agent, opts) do
      :ok -> {:ok, %{data | initial_persistence: :ready}}
      {:error, _reason} = error -> error
    end
  end

  def persist_initial_agent(%State{initial_persistence: :create, state_version: version}),
    do: {:error, {:invalid_initial_revision, version}}

  def persist_initial_agent(%State{} = data),
    do: {:ok, %{data | initial_persistence: :ready}}

  def persist_commit(%State{persistence: nil} = data, agent, version) do
    RuntimeCheckpoint.put(data, agent, version)
  end

  def persist_commit(%State{} = data, agent, version) do
    persist_agent(data, agent, version, :commit)
  end

  def persist_definition_upgrade(%State{persistence: nil} = data, target, version) do
    RuntimeCheckpoint.put(data, target, version)
  end

  def persist_definition_upgrade(%State{agent: %{module: module}} = data, target, version)
      when target.module == module do
    persist_agent(data, target, version, :definition_upgrade)
  end

  def persist_definition_upgrade(%State{} = data, target, version) do
    opts = persistence_write_opts(data, version, :definition_upgrade)
    Jido.Persistence.replace_agent(data.persistence, data.agent, target, opts)
  end

  def persist_agent(data, agent, version, reason, extra_opts \\ [])

  def persist_agent(%State{persistence: nil}, %Agent{}, _version, _reason, _extra_opts),
    do: {:error, :persistence_not_configured}

  def persist_agent(%State{} = data, %Agent{} = agent, version, reason, extra_opts) do
    opts = persistence_write_opts(data, version, reason, extra_opts)
    Jido.Persistence.save_agent(data.persistence, agent, opts)
  end

  def persist_on_stop({:shutdown, :hibernate}, %State{}), do: :ok
  def persist_on_stop({:shutdown, {:persistence_failed, _reason}}, %State{}), do: :ok

  def persist_on_stop(reason, %State{persistence: persistence} = data)
      when not is_nil(persistence) do
    if Shutdown.clean?(reason) do
      case persist_agent(data, data.agent, data.state_version, :stop) do
        :ok ->
          :ok

        {:error, error} ->
          Logger.error("Agent persistence failed during shutdown",
            agent_id: data.agent.id,
            pool: data.pool,
            reason: inspect(error)
          )
      end
    end
  end

  def persist_on_stop(_reason, %State{}), do: :ok

  def delete_runtime_checkpoint(reason, %State{} = data) do
    if Shutdown.clean?(reason), do: RuntimeCheckpoint.delete(data), else: :ok
  end

  defp persistence_write_opts(data, version, reason, extra_opts \\ []) do
    extra_opts
    |> Keyword.put(:instance, data.jido)
    |> Keyword.put(:namespace, data.agent_namespace)
    |> Keyword.put(:partition, data.partition)
    |> Keyword.put(:revision, version)
    |> Keyword.put(:expected_revision, data.state_version)
    |> Keyword.put(:reason, reason)
  end
end
