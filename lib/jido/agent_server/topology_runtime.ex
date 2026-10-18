defmodule Jido.AgentServer.TopologyRuntime do
  @moduledoc false
  alias Jido.Agent
  alias Jido.Agent.Topology
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor

  # Save slot identities with the topology. A removed slot loses its identity,
  # so re-adding that slot cannot restore an earlier member lifetime.
  def identify(before, candidate) do
    with {:ok, desired} <- Topology.bind(candidate, candidate.state),
         {:ok, previous} <- previous_members(before) do
      members =
        Enum.map(candidate.topology.agents, fn declaration ->
          member = Enum.find(desired, &(&1.name == declaration.name))
          old = Enum.find(previous, &(&1.name == member.name))
          same? = old && old.definition == member.definition && old.state == member.state

          retained =
            cond do
              same? ->
                before.topology.agents
                |> Enum.find(&(&1.name == member.name))
                |> Map.get(:identities, %{})

              is_nil(before) ->
                Map.get(declaration, :identities, %{})

              true ->
                %{}
            end

          identities =
            Map.new(1..member.count, fn slot ->
              identity =
                if is_nil(before) or (same? && slot <= old.count),
                  do: Map.get(retained, slot, "initial"),
                  else: Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

              {slot, identity}
            end)

          Map.put(declaration, :identities, identities)
        end)

      {:ok, put_in(candidate.topology.agents, members)}
    end
  end

  defp previous_members(nil), do: {:ok, []}
  defp previous_members(agent), do: Topology.bind(agent, agent.state)

  def validate(agent) do
    with :ok <- Agent.validate_runtime_support(agent),
         {:ok, members} <- Topology.bind(agent, agent.state),
         :ok <- reduce(members, &validate(%{&1.definition | state: &1.state})) do
      supported? =
        Enum.all?(agent.topology.connections, fn edge ->
          Enum.all?([edge.from, edge.to], fn
            %{kind: :agent} -> true
            %{kind: :bus, name: name} -> name in buses(agent)
            _ -> false
          end)
        end)

      if supported?,
        do: :ok,
        else:
          Agent.Error.fail(
            :unsupported_runtime_endpoint,
            [:topology, :connections],
            "Runtime supports Agent and declared local Bus endpoints"
          )
    end
  end

  def changed?(diff, before, after_agent) do
    Agent.Diff.changed?(diff, :agents) or Agent.Diff.changed?(diff, :connections) or
      buses(before) != buses(after_agent) or
      (Agent.Diff.changed?(diff, :state) and
         Topology.bind(before, before.state) != Topology.bind(after_agent, after_agent.state))
  end

  def reconcile(%{agent: agent} = data) do
    with {:ok, members} <- Topology.bind(agent, agent.state) do
      desired =
        Map.new(
          for member <- members, index <- 1..member.count do
            tag = tag(member.name, index)
            declaration = Enum.find(agent.topology.agents, &(&1.name == member.name))
            default = if data.persistence in [nil, false], do: nil, else: "initial"
            identity = Map.get(declaration, :identities, %{}) |> Map.get(index, default)

            {tag,
             %{
               name: member.name,
               slot: index,
               definition: member.definition,
               state: member.state,
               identity: identity
             }}
          end
        )

      previous = plans(data.activation_state)
      live = children(data.activation_state)

      with :ok <- stop_changed(data.owner, previous, desired, live),
           :ok <- start_missing(data, desired, previous, live),
           :ok <- Jido.AgentServer.TopologyBus.reconcile(data) do
        put_plans(data.activation_state, desired)
        {:ok, desired}
      end
    end
  end

  defp stop_changed(owner, previous, desired, live) do
    reduce(previous, fn {tag, old} ->
      if Map.get(desired, tag) != old and Map.has_key?(live, tag),
        do: Server.stop_child(owner, tag),
        else: :ok
    end)
  end

  defp start_missing(data, desired, previous, live) do
    reduce(desired, fn {tag, member} ->
      if Map.get(previous, tag) == member and Map.has_key?(live, tag) do
        Server.await_ready(Map.fetch!(live, tag), data.readiness_timeout)
      else
        id = data.agent.id <> "/" <> tag
        id = if member.identity, do: id <> "/" <> member.identity, else: id

        agent =
          Agent.instantiate!(member.definition,
            id: id,
            state: member.state
          )

        with {:ok, persistence} <- member_persistence(data, agent),
             {:ok, worker} <-
               Server.spawn_child(data.owner, agent, tag,
                 restart: :permanent,
                 server_options: persistence
               ),
             do: Server.await_ready(worker, data.readiness_timeout)
      end
    end)
  end

  defp member_persistence(%{persistence: persistence}, _agent) when persistence in [nil, false],
    do: {:ok, [persistence: false]}

  defp member_persistence(data, agent) do
    options = [instance: data.jido, partition: data.partition]

    case Jido.Persistence.load_agent_with_revision(
           data.persistence,
           agent.module,
           agent.id,
           options
         ) do
      {:ok, _, _} -> {:ok, [persistence: data.persistence, persistence_mode: :restore]}
      {:error, :not_found} -> {:ok, [persistence: data.persistence, persistence_mode: :create]}
      error -> error
    end
  end

  def send_agent(state, name, signal) do
    live = children(state)
    targets = members(state, name)

    case targets do
      [] ->
        case Map.fetch(live, name) do
          {:ok, pid} -> Server.cast(pid, signal)
          :error -> {:error, :agent_not_found}
        end

      pids ->
        reduce(pids, &Server.cast(&1, signal))
    end
  end

  def members(state, name) do
    live = children(state)

    state
    |> plans()
    |> Enum.filter(fn {_, member} -> member.name == name end)
    |> Enum.sort_by(fn {_, member} -> member.slot end)
    |> Enum.flat_map(fn {tag, _member} ->
      case Map.get(live, tag) do
        pid when is_pid(pid) -> [pid]
        _ -> []
      end
    end)
  end

  def owner_send(nil, _), do: {:error, :owner_not_found}

  def owner_send(parent, signal) do
    case ServerSupervisor.worker(parent.activation) do
      pid when is_pid(pid) -> Server.cast(pid, signal)
      _ -> {:error, :owner_not_found}
    end
  end

  def emit(context, signal) do
    with {:ok, edges} <-
           Topology.connections_for(context.agent, %{kind: :agent, name: :root}, signal.type) do
      cond do
        edges != [] ->
          deliver(context, edges, signal)

        topology_parent?(context.parent) ->
          :gen_statem.cast(
            ServerSupervisor.worker(context.parent.activation),
            {:topology_output, context.parent.tag, signal}
          )

          :ok

        true ->
          case context.default_dispatch do
            nil ->
              Server.cast(context.server, signal)

            dispatch ->
              Jido.Signal.Dispatch.dispatch(
                signal,
                Jido.Dispatch.Preparation.inherit_bus_scope(dispatch, context.jido)
              )
          end
      end
    end
  end

  def output(data, source, signal) do
    with {:ok, edges} <- Topology.connections_for(data.agent, source, signal.type),
         do: deliver(data, edges, signal)
  end

  def member_output(data, tag, signal) do
    case Map.fetch(plans(data.activation_state), tag) do
      {:ok, %{name: name}} -> output(data, %{kind: :agent, name: name}, signal)
      :error -> :ok
    end
  end

  defp deliver(data, edges, signal) do
    reduce(edges, fn
      %{to: %{kind: :agent, name: :root}} ->
        Server.cast(data.server, signal)

      %{to: %{kind: :agent, name: name}} ->
        send_agent(data.activation_state, name, signal)

      %{to: %{kind: :bus, name: name}} ->
        Jido.AgentServer.TopologyBus.publish(data.activation_state, name, signal)
    end)
  end

  def buses(agent) do
    for %{provider: Jido.Plugin.Bus.DSL, data: %{buses: buses}} <- agent.extensions,
        bus <- buses,
        do: bus.name
  end

  defp topology_parent?(nil), do: false
  defp topology_parent?(parent), do: Map.has_key?(plans(parent.state), parent.tag)
  defp tag(name, index), do: "$topology/#{name}/#{index}"
  defp plans(nil), do: %{}

  defp plans(state) do
    case :ets.lookup(state, :topology_members) do
      [{_, plans}] -> plans
      [] -> %{}
    end
  end

  defp put_plans(nil, _), do: :ok
  defp put_plans(state, plans), do: :ets.insert(state, {:topology_members, plans})

  defp children(nil), do: %{}

  defp children(state) do
    Map.new(
      for {{:child, tag}, %{root: root}} <- ServerSupervisor.records(state),
          Process.alive?(root),
          pid = ServerSupervisor.worker(root),
          is_pid(pid),
          do: {tag, pid}
    )
  end

  defp reduce(values, fun) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case fun.(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
