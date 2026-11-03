defmodule Jido.AgentServer.Topology do
  @moduledoc false
  use GenServer
  alias Jido.Agent
  alias Jido.Agent.Topology, as: AgentTopology
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{Lifecycle, Effects}
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias Jido.Signal.Bus

  @child_options ~w(placement on_parent_exit orphan_dispatch restart server_options meta)a
  @adoption_options ~w(placement on_parent_exit orphan_dispatch restart meta)a

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @impl true
  def init({context, name}) do
    bus_name =
      "$agent/" <>
        Base.url_encode64(:erlang.term_to_binary({context.partition, context.agent_id, name}),
          padding: false
        )

    with {:ok, bus} <- Bus.start_link(name: bus_name, jido: context.jido),
         {:ok, _subscription} <- Bus.subscribe(bus, "**") do
      owner = :ets.lookup_element(context.state, :worker, 2)
      :ets.insert(context.state, {{:topology_bus, name}, bus})
      {:ok, %{owner: owner, name: name, bus: bus}}
    end
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    :gen_statem.cast(state.owner, {:topology_bus, state.name, signal})
    {:noreply, state}
  end

  def publish(state, name, signal) do
    case :ets.lookup(state, {:topology_bus, name}) do
      [{_, bus}] ->
        case Bus.publish(bus, [signal]) do
          {:ok, _} -> :ok
          error -> error
        end

      [] ->
        {:error, :bus_not_ready}
    end
  end

  def validate(%Agent{} = agent) do
    with :ok <-
           reduce(agent.topology.agents, fn member ->
             with {:ok, child} <- Agent.Validation.resolve(member.definition),
                  do: validate(child)
           end) do
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
          Jido.Error.validation_result(
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
         AgentTopology.bind(before, before.state) !=
           AgentTopology.bind(after_agent, after_agent.state))
  end

  def requires_activation?(agent) do
    not AgentTopology.empty?(agent.topology) or buses(agent) != []
  end

  def spawn_child(server, agent, tag, opts) do
    token = make_ref()

    with {:ok, _agent} <- Agent.Validation.validate_instance(agent),
         {:ok, context, parent} <- child_options(server, tag, opts, token, @child_options),
         :ok <- :gen_statem.call(server, {:reserve_child, tag, token}) do
      try do
        supervisor = child_supervisor(context, parent.placement)

        opts =
          context.opts
          |> Keyword.merge(Keyword.get(opts, :server_options, []))
          |> Keyword.put(:agent, agent)

        spec = %{
          Server.child_spec(opts)
          | start: ServerSupervisor.start_spec(opts, parent),
            restart: parent.restart
        }

        case ServerSupervisor.start_activation(supervisor, spec) do
          {:ok, worker} ->
            {:ok, worker}

          error ->
            ServerSupervisor.release(context.state, tag, token)
            error
        end
      catch
        :exit, reason ->
          ServerSupervisor.release(context.state, tag, token)
          {:error, {:child_start_failed, reason}}
      end
    end
  end

  def children(%{state: nil}), do: %{}

  def children(context) do
    Map.new(
      for {{:child, tag}, %{root: root} = record} <- ServerSupervisor.records(context.state),
          worker = ServerSupervisor.live_worker(root),
          is_pid(worker),
          do: {tag, %{pid: worker, activation: root, placement: record.placement}}
    )
  end

  def stop_child(server, tag, reason) do
    case Map.fetch(Server.children(server), tag) do
      {:ok, %{pid: worker, activation: root, placement: placement}} ->
        context = :gen_statem.call(server, :child_context)
        [{_, record}] = :ets.lookup(context.state, {:child, tag})

        result =
          if Map.get(record, :restart, :transient) == :permanent do
            context
            |> child_supervisor(placement)
            |> DynamicSupervisor.terminate_child(root)
          else
            Server.stop(worker, reason)
          end

        with :ok <- result,
             do: :gen_statem.call(server, {:forget_child, tag, root})

      :error ->
        {:error, :child_not_found}
    end
  end

  def adopt_child(server, child, tag, opts) do
    valid? = unique_options?(opts) and Keyword.get(opts, :placement, :independent) == :independent

    if valid? and Server.alive?(child) do
      token = make_ref()
      opts = Keyword.put(opts, :placement, :independent)

      with {:ok, context, parent} <-
             child_options(server, tag, opts, token, @adoption_options) do
        lock = {{__MODULE__, :adoption, context.jido, context.partition}, self()}

        case :global.trans(
               lock,
               fn -> attach_child(server, child, tag, token, context, parent) end,
               [node()],
               0
             ) do
          :aborted -> {:error, :adoption_busy}
          result -> result
        end
      end
    else
      {:error, :invalid_child_options}
    end
  end

  def reconcile(%{agent: agent} = data) do
    with {:ok, members} <- AgentTopology.bind(agent, agent.state) do
      desired =
        Map.new(
          for member <- members, index <- 1..member.count do
            tag = tag(member.name, index)
            declaration = Enum.find(agent.topology.agents, &(&1.name == member.name))
            default = if data.persistence, do: "initial"
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
      live = live_children(data.activation_state)

      with :ok <- stop_changed(data.owner, previous, desired, live),
           :ok <- start_missing(data, desired, previous, live),
           :ok <- reconcile_buses(data) do
        put_plans(data.activation_state, desired)
        {:ok, desired}
      end
    end
  end

  defp stop_changed(owner, previous, desired, live) do
    reduce(previous, fn {tag, old} ->
      if Map.get(desired, tag) != old and Map.has_key?(live, tag),
        do: stop_child(owner, tag, :shutdown),
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

        with {:ok, agent, persistence} <- member_agent(data, member, id),
             {:ok, worker} <-
               spawn_child(data.owner, agent, tag,
                 restart: :permanent,
                 server_options: persistence
               ),
             do: Server.await_ready(worker, data.readiness_timeout)
      end
    end)
  end

  defp member_agent(%{persistence: persistence} = data, member, id)
       when persistence in [nil, false] do
    with {:ok, agent} <- instantiate_member(data, member, id), do: {:ok, agent, []}
  end

  defp member_agent(data, member, id) do
    options = [instance: data.jido, partition: data.partition]

    case Jido.Persistence.load_agent_with_revision(
           data.persistence,
           member.definition.module,
           id,
           options
         ) do
      {:ok, saved, _revision} ->
        {:ok, saved, [persistence_mode: :restore]}

      {:error, :not_found} ->
        with {:ok, agent} <- instantiate_member(data, member, id),
             do: {:ok, agent, [persistence_mode: :create]}

      error ->
        error
    end
  end

  defp instantiate_member(data, member, id) do
    context = %{parent_id: data.agent.id, member: member.name, slot: member.slot}

    Agent.Validation.instantiate(
      member.definition,
      [id: id, state: member.state],
      context
    )
  end

  def send_agent(state, name, signal) do
    live = live_children(state)
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
    live = live_children(state)

    state
    |> plans()
    |> Enum.filter(fn {_, member} -> member.name == name end)
    |> Enum.sort_by(fn {_, member} -> member.slot end)
    |> Enum.flat_map(fn {tag, _member} ->
      case Map.get(live, tag) do
        nil -> []
        pid -> [pid]
      end
    end)
  end

  def parent_send(nil, _), do: {:error, :parent_not_found}

  def parent_send(parent, signal) do
    case ServerSupervisor.live_worker(parent.activation) do
      nil -> {:error, :parent_not_found}
      pid -> Server.cast(pid, signal)
    end
  end

  def emit(context, signal) do
    with {:ok, edges} <-
           AgentTopology.connections_for(
             context.agent,
             %{kind: :agent, name: :root},
             signal.type
           ) do
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
    with {:ok, edges} <- AgentTopology.connections_for(data.agent, source, signal.type),
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
        publish(data.activation_state, name, signal)
    end)
  end

  def buses(agent) do
    for %{provider: Jido.Plugin.Bus.DSL, data: %{buses: buses}} <- agent.plugins,
        bus <- buses,
        do: bus.name
  end

  defp reconcile_buses(data) do
    names = buses(data.agent)
    existing = if data.activation, do: Supervisor.which_children(data.activation), else: []

    Enum.each(existing, fn
      {{:topology_bus, name} = id, _, _, _} ->
        if name not in names do
          :ok = Supervisor.terminate_child(data.activation, id)
          :ok = Supervisor.delete_child(data.activation, id)
          :ets.delete(data.activation_state, {:topology_bus, name})
        end

      _ ->
        :ok
    end)

    Enum.reduce_while(names, :ok, fn name, :ok ->
      id = {:topology_bus, name}

      if List.keymember?(existing, id, 0) do
        {:cont, :ok}
      else
        context = %{
          state: data.activation_state,
          jido: data.jido,
          partition: data.partition,
          agent_id: data.agent.id
        }

        spec = %{id: id, start: {__MODULE__, :start_link, [{context, name}]}}

        case Supervisor.start_child(data.activation, spec) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end
    end)
  end

  defp topology_parent?(nil), do: false
  defp topology_parent?(parent), do: Map.has_key?(plans(parent.state), parent.tag)
  defp tag(name, index), do: "$topology/#{name}/#{index}"

  defp child_supervisor(context, :owned) do
    {:ok, supervisor} = ServerSupervisor.child_supervisor(context.activation)
    supervisor
  end

  defp child_supervisor(context, :independent), do: Jido.agent_supervisor_name(context.jido)

  defp attach_child(server, child, tag, token, context, parent) do
    with :ok <- validate_adoption(context, child),
         :ok <- :gen_statem.call(server, {:reserve_child, tag, token}) do
      try do
        result = :gen_statem.call(child, {:attach_parent, parent})
        if result != :ok, do: ServerSupervisor.release(context.state, tag, token)
        result
      catch
        :exit, _ ->
          ServerSupervisor.release(context.state, tag, token)
          {:error, :child_unavailable}
      end
    end
  end

  defp validate_adoption(context, child) do
    root = Server.activation(child)

    cond do
      is_nil(root) ->
        {:error, :activation_required}

      root == context.activation ->
        {:error, :self_adoption}

      true ->
        case ancestor?(context.activation, root, []) do
          true -> {:error, :cyclic_parent}
          false -> :ok
          error -> error
        end
    end
  catch
    :exit, _ -> {:error, :child_unavailable}
  end

  @spec ancestor?(pid(), pid(), [pid()]) :: boolean() | {:error, atom()}
  defp ancestor?(root, root, _visited), do: true

  defp ancestor?(current, root, visited) do
    if current in visited do
      true
    else
      worker = ServerSupervisor.worker(current)

      case :gen_statem.call(worker, :parent) do
        nil -> false
        parent -> ancestor?(parent.activation, root, [current | visited])
      end
    end
  catch
    :exit, _ -> {:error, :ancestor_unavailable}
  end

  defp child_options(server, tag, opts, token, allowed) do
    if unique_options?(opts) and Keyword.keys(opts) -- allowed == [] do
      context = :gen_statem.call(server, :child_context)
      placement = Keyword.get(opts, :placement, :owned)
      policy = Keyword.get(opts, :on_parent_exit, :stop)
      dispatch = opts[:orphan_dispatch]
      server_options = Keyword.get(opts, :server_options, [])
      meta = Keyword.get(opts, :meta, %{})

      cond do
        is_nil(context.activation) ->
          {:error, :activation_required}

        Server.Directive.validate_restart_policy(Keyword.get(opts, :restart, :transient)) != :ok ->
          {:error, :invalid_restart_policy}

        not valid_server_options?(server_options) ->
          {:error, :invalid_child_options}

        not is_map(meta) or is_struct(meta) ->
          {:error, :invalid_child_options}

        not (is_atom(tag) or is_binary(tag)) or is_nil(tag) ->
          {:error, :invalid_child_tag}

        placement not in [:owned, :independent] ->
          {:error, :invalid_placement}

        policy not in [:stop, :continue, :emit_orphan] ->
          {:error, :invalid_parent_policy}

        placement == :owned and policy != :stop ->
          {:error, :owned_child_cannot_survive_parent}

        placement == :independent and is_nil(context.jido) ->
          {:error, :jido_instance_required}

        policy == :emit_orphan and
            (is_nil(dispatch) or Effects.validate_dispatch(dispatch) != :ok) ->
          {:error, :invalid_orphan_dispatch}

        true ->
          {:ok, context,
           %{
             restart: Keyword.get(opts, :restart, :transient),
             meta: meta,
             activation: context.activation,
             state: context.state,
             token: token,
             agent_id: context.agent_id,
             tag: tag,
             placement: placement,
             policy: policy,
             dispatch: dispatch,
             jido: context.jido,
             partition: context.partition
           }}
      end
    else
      {:error, :invalid_child_options}
    end
  end

  defp unique_options?(opts) do
    Keyword.keyword?(opts) and
      length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts)))
  end

  defp valid_server_options?(opts) do
    Lifecycle.unique_keyword?(opts) and Keyword.keys(opts) -- Lifecycle.runtime_keys() == []
  end

  defp plans(state) do
    case :ets.lookup(state, :topology_members) do
      [{_, plans}] -> plans
      [] -> %{}
    end
  end

  defp put_plans(state, plans), do: :ets.insert(state, {:topology_members, plans})

  defp live_children(state) do
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
      result = fun.(value)
      {if(result == :ok, do: :cont, else: :halt), result}
    end)
  end
end
