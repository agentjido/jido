defmodule Jido.AgentServer.RuntimeDirectives do
  @moduledoc false
  alias Jido.Agent
  alias Jido.AgentServer, as: Server

  def validate_target(name, config) do
    cond do
      is_nil(config.activation) -> {:error, :activation_required}
      not (is_atom(name) or is_binary(name)) or name in [nil, ""] -> {:error, :invalid_agent_name}
      String.starts_with?(to_string(name), "$topology/") -> {:error, :reserved_agent_name}
      true -> :ok
    end
  end

  def validate_runtime_target(name, config) do
    with :ok <- validate_target(name, config) do
      if Enum.any?(config.agent.topology.agents, &(&1.name == name)),
        do: {:error, :topology_agent_requires_mutation},
        else: :ok
    end
  end

  def validate_start(directive, config) do
    with :ok <- validate_runtime_target(directive.name, config),
         :ok <- local_node(directive.node),
         {:ok, _agent, options} <- prepare(directive, config.agent.id),
         {:ok, _} <-
           Server.activation_options(
             Keyword.merge(
               [jido: config.jido, partition: config.partition, runner: config.runner],
               options
             )
           ) do
      :ok
    end
  end

  defp local_node(target) when target in [nil, node()], do: :ok
  defp local_node(_), do: {:error, :remote_agent_start_not_supported}

  def start(directive, context) do
    with {:ok, agent, options} <- prepare(directive, context.agent.id),
         {:ok, pid} <-
           Server.spawn_child(context.server, agent, directive.name,
             restart: directive.restart,
             server_options: options,
             meta: directive.meta
           ),
         do: Server.await_ready(pid)
  end

  defp prepare(directive, owner_id) do
    opts = Map.to_list(directive.opts)
    id = Keyword.get(opts, :id, owner_id <> "/" <> to_string(directive.name))
    state = Keyword.get(opts, :state, %{})
    options = opts |> Keyword.drop([:id, :state]) |> Keyword.put_new(:persistence, false)

    case directive.agent do
      %Agent{id: id} = agent when is_binary(id) ->
        if Keyword.has_key?(opts, :id) or Keyword.has_key?(opts, :state),
          do: {:error, :instance_options_conflict},
          else: {:ok, agent, Keyword.put(options, :agent, agent)}

      definition ->
        with {:ok, definition} <- Agent.Validation.resolve(definition),
             {:ok, agent} <- Agent.instantiate(definition, id: id, state: state),
             do: {:ok, agent, Keyword.put(options, :agent, agent)}
    end
  end
end
