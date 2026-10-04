defmodule Jido.Topology.Controller.Activation do
  @moduledoc false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Topology.{BusInputs, Validation}

  def start(spec, context) do
    child = %{
      id: spec.key,
      start: {__MODULE__, :start_link, [spec, context]},
      restart: :transient,
      modules: [Server]
    }

    result =
      if spec.node == node() and node(context.owner) == node() do
        Supervisor.start_child(context.agents, child)
      else
        DynamicSupervisor.start_child(
          Jido.agent_supervisor_name(context.jido),
          %{child | restart: :temporary}
        )
      end

    case result do
      {:ok, pid} ->
        Jido.Topology.Controller.Owner.track(context.owner, pid)
        await_member(pid)

      {:error, {:already_started, pid}} ->
        await_member(pid)

      {:error, :already_present} ->
        {:error, :member_stopped}

      error ->
        error
    end
  end

  defp await_member(pid) do
    case Server.await_ready(pid) do
      :ok -> {:ok, pid}
      {:error, reason} -> {:error, {:member_start_failed, reason}}
    end
  end

  # OTP invokes this function on each restart. Keep state recovery in core
  # and rebuild the declared configuration before every start.
  def start_link(spec, context) do
    with {:ok, definition} <- definition(spec, context) do
      Server.start_link(
        agent: definition,
        id: spec.id,
        initial_state: spec.initial_state,
        jido: context.jido,
        on_parent_death: spec.on_parent_exit,
        restore_definition: :current,
        checkpoint_owner: Map.get(context, :checkpoint_owner)
      )
    end
  end

  def start_on_node(spec, context) do
    :erpc.call(spec.node, __MODULE__, :start, [spec, context], context.task_timeout)
  catch
    :error, {:erpc, reason} when reason in [:timeout, :noconnection] ->
      {:error, {:placement_uncertain, spec.node, reason}}

    :error, {:erpc, reason} ->
      {:error, {:remote_activation_failed, spec.node, reason}}

    kind, reason ->
      {:error, {:placement_uncertain, spec.node, {kind, reason}}}
  end

  defp definition(spec, context) do
    with {:ok, definition} <- Validation.agent_definition(Validation.agent_source(spec)) do
      metadata =
        Map.put(definition.metadata, "jido.topology", %{
          id: context.instance_id,
          key: spec.key
        })

      # Topology owns this derived static definition. It is not the exact
      # generated module definition, so it uses the compatible unversioned form.
      definition = %{definition | metadata: metadata, vsn: nil}

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
