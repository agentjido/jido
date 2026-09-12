defmodule Jido.AgentServer.Persistence do
  @moduledoc false

  require Logger

  alias Jido.Agent
  alias Jido.AgentServer.{Options, RuntimeCheckpoint, State}

  @doc false
  @spec restore_initial(Options.t()) ::
          {:ok, Agent.t(), non_neg_integer(), :none | :create | :restored} | {:error, term()}
  def restore_initial(%Options{restore: false, persistence: nil} = opts) do
    {:ok, opts.agent, opts.state_version, :none}
  end

  def restore_initial(%Options{restore: false} = opts) do
    {:ok, opts.agent, opts.state_version, :create}
  end

  def restore_initial(%Options{persistence: nil, restore: :required}) do
    {:error, :persistence_not_configured}
  end

  def restore_initial(%Options{persistence: nil} = opts) do
    {agent, version} = RuntimeCheckpoint.restore(opts)
    {:ok, agent, version, :none}
  end

  def restore_initial(%Options{} = opts) do
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

  @doc false
  @spec persist_initial(State.t()) :: {:ok, State.t()} | {:error, term()}
  def persist_initial(%State{initial_persistence: :create, state_version: 0} = data) do
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

  def persist_initial(%State{initial_persistence: :create, state_version: version}),
    do: {:error, {:invalid_initial_revision, version}}

  def persist_initial(%State{} = data),
    do: {:ok, %{data | initial_persistence: :ready}}

  @doc false
  @spec commit(State.t(), Agent.t(), non_neg_integer()) :: :ok | {:error, term()}
  def commit(%State{persistence: nil} = data, agent, version) do
    RuntimeCheckpoint.put(data, agent, version)
  end

  def commit(%State{} = data, agent, version) do
    persist(data, agent, version, :commit)
  end

  @doc false
  @spec persist(State.t(), Agent.t(), non_neg_integer(), atom(), keyword()) ::
          :ok | {:error, term()}
  def persist(data, agent, version, reason, extra_opts \\ [])

  def persist(%State{persistence: nil}, %Agent{}, _version, _reason, _extra_opts),
    do: {:error, :persistence_not_configured}

  def persist(%State{} = data, %Agent{} = agent, version, reason, extra_opts) do
    opts =
      extra_opts
      |> Keyword.put(:instance, data.jido)
      |> Keyword.put(:namespace, data.agent_namespace)
      |> Keyword.put(:partition, data.partition)
      |> Keyword.put(:revision, version)
      |> Keyword.put(:expected_revision, data.state_version)
      |> Keyword.put(:reason, reason)

    Jido.Persistence.save_agent(data.persistence, agent, opts)
  end

  @doc false
  @spec persist_on_stop(term(), State.t()) :: :ok | nil
  def persist_on_stop({:shutdown, :hibernate}, %State{}), do: :ok
  def persist_on_stop({:shutdown, {:persistence_failed, _reason}}, %State{}), do: :ok

  def persist_on_stop(reason, %State{persistence: persistence} = data)
      when not is_nil(persistence) do
    if clean_shutdown?(reason) do
      case persist(data, data.agent, data.state_version, :stop) do
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

  @doc false
  @spec delete_runtime_checkpoint(term(), State.t()) :: :ok | {:error, term()}
  def delete_runtime_checkpoint(reason, %State{} = data) do
    if clean_shutdown?(reason), do: RuntimeCheckpoint.delete(data), else: :ok
  end

  @doc false
  @spec clean_shutdown?(term()) :: boolean()
  def clean_shutdown?(:normal), do: true
  def clean_shutdown?(:shutdown), do: true
  def clean_shutdown?({:shutdown, _reason}), do: true
  def clean_shutdown?(_reason), do: false
end
