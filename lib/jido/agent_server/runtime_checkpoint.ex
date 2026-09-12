defmodule Jido.AgentServer.RuntimeCheckpoint do
  @moduledoc false

  alias Jido.Agent
  alias Jido.AgentServer.{Options, State}
  alias Jido.RuntimeStore

  @hive :agent_runtime_checkpoints

  @doc false
  @spec restore(Options.t()) :: {Agent.t(), non_neg_integer()}
  def restore(%Options{agent: %Agent{} = initial} = options) do
    case fetch(options.jido, key(initial.id, options.partition)) do
      {:ok, %{agent: %Agent{} = agent, state_version: version}}
      when agent.id == initial.id and agent.module == initial.module and
             is_integer(version) and version >= 0 ->
        {agent, version}

      {:ok,
       %{
         agent: %Agent{} = agent,
         state_version: version,
         upgrade_from_module: source_module
       }}
      when agent.id == initial.id and source_module == initial.module and
             is_integer(version) and version >= 0 ->
        {agent, version}

      _other ->
        {initial, options.state_version}
    end
  end

  @doc false
  @spec put(State.t(), Agent.t(), non_neg_integer()) :: :ok | {:error, term()}
  def put(
        %State{jido: jido, partition: partition, agent: %Agent{} = current},
        %Agent{} = agent,
        state_version
      )
      when is_atom(jido) and not is_nil(jido) do
    checkpoint_key = key(agent.id, partition)
    source_module = existing_source_module(jido, checkpoint_key, current)

    RuntimeStore.put(
      jido,
      @hive,
      checkpoint_key,
      checkpoint(agent, state_version, source_module)
    )
  end

  def put(%State{}, %Agent{}, _state_version), do: :ok

  @doc false
  @spec put_upgrade(State.t(), Agent.t(), non_neg_integer()) :: :ok | {:error, term()}
  def put_upgrade(
        %State{jido: jido, partition: partition, agent: current},
        %Agent{} = target,
        state_version
      )
      when is_atom(jido) and not is_nil(jido) do
    checkpoint_key = key(target.id, partition)
    source_module = existing_source_module(jido, checkpoint_key, current) || current.module

    RuntimeStore.put(
      jido,
      @hive,
      checkpoint_key,
      checkpoint(target, state_version, source_module)
    )
  end

  def put_upgrade(%State{}, %Agent{}, _state_version), do: :ok

  @doc false
  @spec delete(State.t()) :: :ok | {:error, term()}
  def delete(%State{jido: jido, agent: agent, partition: partition})
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.delete(jido, @hive, key(agent.id, partition))
  end

  def delete(%State{}), do: :ok

  defp fetch(jido, key) when is_atom(jido) and not is_nil(jido),
    do: RuntimeStore.fetch(jido, @hive, key)

  defp fetch(_jido, _key), do: :error

  defp existing_source_module(jido, checkpoint_key, %Agent{} = current) do
    case RuntimeStore.fetch(jido, @hive, checkpoint_key) do
      {:ok,
       %{
         agent: %Agent{id: id, module: module},
         upgrade_from_module: source_module
       }}
      when id == current.id and module == current.module and is_atom(source_module) and
             not is_nil(source_module) ->
        source_module

      _other ->
        nil
    end
  end

  defp checkpoint(agent, state_version, nil) do
    %{agent: agent, state_version: state_version}
  end

  defp checkpoint(agent, state_version, source_module) do
    %{
      agent: agent,
      state_version: state_version,
      upgrade_from_module: source_module
    }
  end

  defp key(agent_id, partition), do: Jido.partition_key(agent_id, partition)
end
