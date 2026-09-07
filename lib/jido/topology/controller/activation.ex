defmodule Jido.Topology.Controller.Activation do
  @moduledoc false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Topology.{BusInputs, Validation}

  def start(spec, context) do
    with {:ok, persistence} <- Jido.Persistence.resolve_config(:inherit, context.jido),
         {:ok, agent_state, version, restore} <- saved_state(spec, context, persistence),
         {:ok, definition} <- definition(spec, context),
         {:ok, agent} <- Agent.instantiate(definition, id: spec.id, state: agent_state) do
      options = [
        agent: agent,
        jido: context.jido,
        register: true,
        on_parent_death: spec.on_parent_exit,
        persistence: persistence,
        restore: restore,
        state_version: version
      ]

      child = Supervisor.child_spec({Server, options}, restart: :temporary)
      pool = Jido.agent_supervisor_name(context.jido)

      with {:ok, pid} <- DynamicSupervisor.start_child(pool, child) do
        case Server.await_ready(pid) do
          :ok ->
            {:ok, pid}

          {:error, _} = error ->
            DynamicSupervisor.terminate_child(pool, pid)
            error
        end
      end
    end
  end

  defp saved_state(spec, _state, nil), do: {:ok, spec.initial_state, 0, :if_found}

  defp saved_state(spec, context, persistence) do
    case Jido.Persistence.load_agent_with_revision(persistence, spec.module, spec.id,
           instance: context.jido
         ) do
      {:ok, agent, version} when agent.id == spec.id and agent.module == spec.module ->
        {:ok, agent.state, version, false}

      {:ok, _, _} ->
        {:error, :restored_agent_identity_mismatch}

      {:error, :not_found} ->
        {:ok, spec.initial_state, 0, false}

      {:error, _} = error ->
        error
    end
  end

  defp definition(spec, context) do
    with {:ok, definition} <- Validation.agent_definition(spec.module) do
      metadata =
        Map.put(definition.metadata, "jido.topology", %{
          id: context.instance_id,
          key: spec.key
        })

      definition = %{definition | metadata: metadata}

      definition =
        if spec.subscriptions == [] do
          definition
        else
          subscriptions =
            Enum.map(spec.subscriptions, fn sub ->
              [
                bus: Map.fetch!(context.bus_ids, sub.bus),
                path: sub.path,
                retry_delay_ms: context.retry_interval
              ]
            end)

          %{
            definition
            | plugins: definition.plugins ++ [{BusInputs, subscriptions: subscriptions}]
          }
        end

      Agent.new(definition)
    end
  end
end
