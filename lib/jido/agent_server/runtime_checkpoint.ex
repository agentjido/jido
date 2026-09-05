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

      _other ->
        {initial, options.state_version}
    end
  end

  @doc false
  @spec put(State.t(), Agent.t(), non_neg_integer()) :: :ok | {:error, term()}
  def put(%State{jido: jido, partition: partition}, %Agent{} = agent, state_version)
      when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.put(jido, @hive, key(agent.id, partition), %{
      agent: agent,
      state_version: state_version
    })
  end

  def put(%State{}, %Agent{}, _state_version), do: :ok

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

  defp key(agent_id, partition), do: Jido.partition_key(agent_id, partition)
end
