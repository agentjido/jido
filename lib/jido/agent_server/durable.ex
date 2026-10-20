defmodule Jido.AgentServer.Durable do
  @moduledoc false

  alias Jido.AgentServer.{DurableTurn, Supervisor, TopologyRuntime}

  @max_timeout 4_294_967_295

  def validate_runtime(opts) do
    cond do
      enabled?(opts[:persistence]) and is_nil(opts[:jido]) ->
        invalid("persistence requires a Jido instance with a stable namespace")

      not (is_integer(opts[:persistence_timeout]) and
               opts[:persistence_timeout] in 0..@max_timeout) ->
        invalid("invalid persistence_timeout")

      opts[:persistence_mode] not in [:create, :restore] ->
        invalid("invalid persistence_mode")

      opts[:idle_policy] == :hibernate and not enabled?(opts[:persistence]) ->
        invalid("invalid idle_policy")

      true ->
        :ok
    end
  end

  def start(data, mode) do
    with :ok <- Supervisor.close_execution(data.activation_state),
         {:ok, config} <- Jido.Persistence.resolve_config(data.persistence, data.jido),
         {:ok, agent, revision, turn} <- load(config, data.agent, mode, options(data)),
         {:ok, agent} <- Jido.Agent.Validation.validate_instance(agent),
         :ok <- DurableTurn.validate_restore(agent, turn) do
      {:ok, agent, revision, config, turn}
    end
  end

  def save(data, agent, revision, expected_revision, server_turn) do
    Jido.Persistence.save_agent(
      data.persistence,
      agent,
      options(data) ++
        [
          revision: revision,
          expected_revision: expected_revision,
          server_turn: server_turn
        ]
    )
  end

  def write_result(result, deadline) do
    if System.monotonic_time(:millisecond) >= deadline,
      do: {:error, :indeterminate},
      else: result
  end

  def resumable?(reason),
    do: reason not in [:conflict, :indeterminate] and not match?({:indeterminate, _}, reason)

  def error(reason, resumable?), do: {:error, %{reason: reason, resumable?: resumable?}}

  def snapshot(agent, revision), do: %{agent: agent, state_version: revision}

  def upgrade(agent, action, context) do
    with {:ok, snapshot} <- Jido.Persistence.snapshot(agent, context: context),
         do: Jido.Persistence.upgrade(snapshot, action, context: context)
  end

  @doc false
  def persistence_mode(state, requested) do
    lifetime = :ets.lookup_element(state, :durable_lifetime, 2)

    if :atomics.get(lifetime, 1) == 1 or not :ets.insert_new(state, {:durable_started, true}),
      do: :restore,
      else: requested
  end

  @doc false
  def restore(state, agent, revision) do
    # The parent child specification retains this reference across root loss.
    # A separate start has a new reference and still enforces strict :create.
    lifetime = :ets.lookup_element(state, :durable_lifetime, 2)
    :atomics.put(lifetime, 1, 1)
    :ets.insert(state, {:checkpoint, agent, revision})
  end

  defp load(config, agent, :create, opts) do
    with {:ok, agent} <- Jido.Agent.Composition.bind(agent),
         {:ok, agent} <- TopologyRuntime.identify(nil, agent),
         :ok <- Jido.Persistence.create_agent(config, agent, opts),
         do: {:ok, agent, 0, nil}
  end

  defp load(config, agent, :restore, opts),
    do: Jido.Persistence.load_agent_with_server_turn(config, agent.module, agent.id, opts)

  defp options(data), do: [instance: data.jido, partition: data.partition]
  defp enabled?(source), do: source not in [nil, false]
  defp invalid(message), do: {:error, Jido.Error.validation_error(message, kind: :config)}
end
