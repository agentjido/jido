defmodule Jido.Topology.Controller.Runtime do
  @moduledoc false
  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Telemetry.Topology, as: TopologyTelemetry
  alias Jido.Topology.{BusInputs, Controller, Plan, Resource}

  alias Jido.Topology.Signal.{
    ComponentFailed,
    ComponentReady,
    OperationCompleted,
    OperationStarted,
    StatusChanged
  }

  alias Jido.Tracing.Context, as: TraceContext

  @placement_hive :topology_placements

  def start_link({jido, instance, repair, lifecycle}),
    do: GenServer.start_link(__MODULE__, {jido, instance, repair, lifecycle})

  @impl true
  def init({jido, instance, repair, lifecycle}) do
    Process.flag(:trap_exit, true)

    state = %{
      jido: jido,
      instance: instance,
      repair: repair,
      lifecycle: lifecycle,
      reconcile_requested: false,
      reconcile_timer: nil,
      reconcile_token: nil,
      ready: %{},
      errors: %{},
      waiters: %{},
      phase: :starting,
      pending: MapSet.new(),
      active: %{},
      pass_count: 0,
      operation_span: nil,
      operation: nil,
      operation_id: nil,
      operation_override: nil,
      last_status: nil,
      placements: load_placements(jido, instance)
    }

    {:ok, state, {:continue, :reconcile}}
  end

  @impl true
  def handle_continue(:reconcile, state), do: {:noreply, begin_pass(state)}

  @impl true
  def handle_info({:reconcile, token}, %{reconcile_token: token} = state) when not is_nil(token),
    do: {:noreply, request_pass(state)}

  def handle_info({:reconcile, _token}, state), do: {:noreply, state}

  def handle_info({ref, result}, state) when is_reference(ref),
    do: {:noreply, complete(state, ref, result)}

  def handle_info({:DOWN, ref, :process, _pid, reason}, state),
    do: {:noreply, complete(state, ref, {:error, reason})}

  def handle_info({:task_timeout, ref}, state) do
    case Map.get(state.active, ref) do
      nil ->
        {:noreply, state}

      job ->
        Process.exit(job.task.pid, :kill)
        {:noreply, %{state | active: Map.put(state.active, ref, %{job | timed_out?: true})}}
    end
  end

  def handle_info({:expire_waiter, token}, state),
    do: {:noreply, %{state | waiters: Map.delete(state.waiters, token)}}

  @impl true
  def handle_call(:status, _from, state) do
    state = refresh_phase(state)

    {:reply,
     %{
       status: current_phase(state),
       repair: state.repair,
       agents: map_size(state.instance.plan.agents),
       resources: map_size(state.instance.plan.resources),
       ready: map_size(state.ready),
       errors: state.errors,
       components: state.instance.plan.components,
       active: map_size(state.active),
       pending: MapSet.size(state.pending)
     }, state}
  end

  def handle_call(:reconcile, _from, state), do: {:reply, :ok, request_pass(state)}

  def handle_call({:update, target}, _from, state) do
    with :ok <- update_idle(state),
         :ok <- additive_target(state.instance, target),
         :ok <- save_placements(state.jido, target, Map.get(state, :placements, %{})) do
      state =
        state
        |> Map.put(:instance, target)
        |> Map.put(:operation_override, :update)
        |> request_pass()

      {:reply, :ok, state}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:place_agent, target, member, target_node, timeout}, _from, state) do
    with :ok <- update_idle(state),
         {:ok, key, current} <- placement_target(state, target, member),
         :ok <- placement_node(target_node),
         :ok <- placement_resources(current, target_node) do
      if current.node == target_node do
        {:reply, :ok, state}
      else
        with :ok <- retire(current, state, timeout) do
          placements = Map.put(Map.get(state, :placements, %{}), key, target_node)

          case save_placements(state.jido, state.instance, placements) do
            :ok ->
              state =
                state
                |> Map.put(:placements, placements)
                |> Map.update!(:ready, &Map.delete(&1, key))
                |> Map.update!(:errors, &Map.delete(&1, key))
                |> Map.put(:operation_override, :place)
                |> request_pass()

              {:reply, :ok, state}

            {:error, _reason} = error ->
              {:reply, error, request_pass(state)}
          end
        else
          {:error, _reason} = error -> {:reply, error, state}
        end
      end
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:await_ready, timeout}, from, state) do
    state = refresh_phase(state)

    if state.phase == :ready do
      {:reply, :ok, state}
    else
      token = make_ref()

      timer =
        if timeout == :infinity,
          do: nil,
          else: Process.send_after(self(), {:expire_waiter, token}, timeout)

      {:noreply, %{state | waiters: Map.put(state.waiters, token, {from, timer})}}
    end
  end

  def handle_call({:agent, target, member}, _from, state) do
    key = Plan.resolve(state.instance.plan, target, :agent, member)
    context = ownership_context(state)

    pid =
      case agent_spec(key, state) do
        nil ->
          nil

        spec ->
          case whereis_agent(spec, %{jido: state.jido}) do
            pid when is_pid(pid) -> if owned?(:agent, pid, spec, context), do: pid
            _ -> nil
          end
      end

    {:reply, pid, state}
  end

  def handle_call({:agent_node, target, member}, _from, state) do
    key = Plan.resolve(state.instance.plan, target, :agent, member)

    target_node =
      case agent_spec(key, state) do
        nil -> nil
        spec -> spec.node
      end

    {:reply, target_node, state}
  end

  def handle_call({:bus, target}, _from, state) do
    key = Plan.resolve(state.instance.plan, target, :bus)
    context = ownership_context(state)

    pid =
      case Map.get(state.instance.plan.resources, key) do
        nil ->
          nil

        spec ->
          Resource.whereis(spec, context)
      end

    {:reply, pid, state}
  end

  @impl true
  def terminate(reason, state) do
    TopologyTelemetry.finish(Map.get(state, :operation_span), :error, state)
    span = TopologyTelemetry.start(:cleanup, state)
    operation_id = Jido.Signal.ID.generate!()

    emit(state, fn ->
      lifecycle_signal(OperationStarted, state.instance.id, %{
        operation_id: operation_id,
        operation: "cleanup"
      })
    end)

    if state.reconcile_timer, do: Process.cancel_timer(state.reconcile_timer)
    Enum.each(state.active, fn {_, job} -> Task.shutdown(job.task, :brutal_kill) end)

    if intentional_shutdown?(reason) do
      context = ownership_context(state)

      state.instance.plan.layers
      |> Enum.reverse()
      |> List.flatten()
      |> Enum.each(fn key ->
        case agent_spec(key, state) do
          nil ->
            :ok

          spec ->
            safely(fn ->
              case whereis_agent(spec, %{jido: state.jido}) do
                pid when is_pid(pid) ->
                  if owned?(:agent, pid, spec, context) do
                    stop_agent(
                      state.jido,
                      pid,
                      state.instance.definition.startup.task_timeout
                    )
                  end

                _ ->
                  :ok
              end
            end)
        end
      end)

      Jido.RuntimeStore.delete(state.jido, @placement_hive, state.instance.id)
    end

    cleanup_status = if intentional_shutdown?(reason), do: :ok, else: :error
    TopologyTelemetry.finish(span, cleanup_status, %{state | ready: %{}})

    emit(state, fn ->
      lifecycle_signal(OperationCompleted, state.instance.id, %{
        operation_id: operation_id,
        operation: "cleanup",
        status: Atom.to_string(cleanup_status)
      })
    end)

    :ok
  end

  defp current_phase(state), do: state.phase

  defp update_idle(%{active: active}) when map_size(active) == 0, do: :ok

  defp update_idle(_state),
    do: Jido.Agent.Authoring.error("Topology update or placement requires an idle repair pass")

  defp additive_target(%{id: id} = current, %{id: id} = target) do
    current_agents = current.plan.agents
    target_agents = target.plan.agents

    removed = Map.keys(current_agents) -- Map.keys(target_agents)

    changed =
      current_agents
      |> Map.keys()
      |> Enum.filter(&(Map.get(target_agents, &1) != Map.fetch!(current_agents, &1)))

    cond do
      current.plan.resources != target.plan.resources ->
        Jido.Agent.Authoring.error("Topology update cannot change resources")

      removed != [] ->
        Jido.Agent.Authoring.error("Topology update cannot remove Agents", %{
          removed: Enum.sort(removed)
        })

      changed != [] ->
        Jido.Agent.Authoring.error("Topology update cannot change existing Agents", %{
          changed: Enum.sort(changed)
        })

      true ->
        :ok
    end
  end

  defp additive_target(_current, _target),
    do: Jido.Agent.Authoring.error("Topology update identity does not match")

  defp request_pass(state) do
    if state.reconcile_timer, do: Process.cancel_timer(state.reconcile_timer)
    state = %{state | reconcile_timer: nil, reconcile_token: nil}

    if map_size(state.active) > 0,
      do: %{state | reconcile_requested: true},
      else: begin_pass(state)
  end

  defp begin_pass(state) do
    keys = Map.keys(state.instance.plan.agents) ++ Map.keys(state.instance.plan.resources)

    operation =
      state.operation_override ||
        if(Map.get(state, :pass_count, 0) == 0, do: :activate, else: :repair)

    operation_id = Jido.Signal.ID.generate!()
    span = TopologyTelemetry.start(operation, state)

    emit(state, fn ->
      lifecycle_signal(OperationStarted, state.instance.id, %{
        operation_id: operation_id,
        operation: Atom.to_string(operation)
      })
    end)

    state
    |> Map.merge(%{
      ready: %{},
      errors: %{},
      pending: MapSet.new(keys),
      phase: :starting,
      reconcile_requested: false,
      operation_span: span,
      operation: operation,
      operation_id: operation_id,
      operation_override: nil
    })
    |> drive()
  end

  defp drive(state) do
    capacity = state.instance.definition.startup.concurrency - map_size(state.active)

    runnable =
      state.pending
      |> Enum.filter(&dependencies_ready?(&1, state))
      |> Enum.sort()
      |> Enum.take(capacity)

    state = Enum.reduce(runnable, state, &dispatch/2)

    cond do
      map_size(state.active) > 0 ->
        state

      MapSet.size(state.pending) > 0 ->
        state =
          Enum.reduce(state.pending, state, fn key, state ->
            missing = Enum.reject(spec(key, state).depends_on, &Map.has_key?(state.ready, &1))
            record(state, key, {:error, {:dependencies_unavailable, missing}})
          end)

        finish_pass(%{state | pending: MapSet.new()})

      true ->
        finish_pass(state)
    end
  end

  defp dependencies_ready?(key, state),
    do: Enum.all?(spec(key, state).depends_on, &Map.has_key?(state.ready, &1))

  defp spec(key, state),
    do: agent_spec(key, state) || Map.fetch!(state.instance.plan.resources, key)

  defp agent_spec(nil, _state), do: nil

  defp agent_spec(key, state) do
    case Map.get(state.instance.plan.agents, key) do
      nil -> nil
      spec -> Map.put(spec, :node, Map.get(Map.get(state, :placements, %{}), key, spec.node))
    end
  end

  defp dispatch(key, state) do
    supervisor = Controller.name(state.jido, state.instance.id, :tasks)

    member = spec(key, state)
    context = task_context(key, member, state)
    trace = TraceContext.capture()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        TraceContext.with_context(trace, fn -> safely(fn -> ensure(member, context) end) end)
      end)

    timer =
      Process.send_after(
        self(),
        {:task_timeout, task.ref},
        state.instance.definition.startup.task_timeout
      )

    job = %{key: key, task: task, timer: timer, timed_out?: false}

    %{
      state
      | pending: MapSet.delete(state.pending, key),
        active: Map.put(state.active, task.ref, job)
    }
  end

  defp complete(state, ref, result) do
    case Map.pop(state.active, ref) do
      {nil, _} ->
        state

      {job, active} ->
        Process.demonitor(ref, [:flush])
        Process.cancel_timer(job.timer)
        result = if job.timed_out?, do: {:error, :startup_task_timeout}, else: result
        %{state | active: active} |> record(job.key, result) |> drive()
    end
  end

  defp record(state, key, {:ok, pid}) do
    emit(state, fn ->
      lifecycle_signal(
        ComponentReady,
        state.instance.id,
        component_data(Map.get(state, :operation_id), spec(key, state))
      )
    end)

    %{state | ready: Map.put(state.ready, key, pid)}
  end

  defp record(state, key, {:error, reason}) do
    emit(state, fn ->
      lifecycle_signal(
        ComponentFailed,
        state.instance.id,
        Map.put(
          component_data(Map.get(state, :operation_id), spec(key, state)),
          :reason,
          reason_code(reason)
        )
      )
    end)

    %{state | errors: Map.put(state.errors, key, reason)}
  end

  defp finish_pass(%{reconcile_requested: true} = state) do
    state = complete_pass(state)
    begin_pass(%{state | reconcile_requested: false})
  end

  defp finish_pass(state) do
    state = complete_pass(state)

    if state.phase == :ready do
      reply_waiters(state)
    else
      schedule_reconcile(state)
    end
  end

  defp complete_pass(state) do
    state = recheck_ready(state)
    phase = if map_size(state.errors) == 0, do: :ready, else: :degraded

    TopologyTelemetry.finish(
      Map.get(state, :operation_span),
      if(phase == :ready, do: :ok, else: :error),
      state
    )

    emit(state, fn ->
      lifecycle_signal(OperationCompleted, state.instance.id, %{
        operation_id: Map.get(state, :operation_id),
        operation: state |> Map.get(:operation, :repair) |> Atom.to_string(),
        status: Atom.to_string(phase)
      })
    end)

    if Map.get(state, :last_status) != phase do
      emit(state, fn ->
        lifecycle_signal(StatusChanged, state.instance.id, %{
          operation_id: Map.get(state, :operation_id),
          previous: status(Map.get(state, :last_status)),
          current: Atom.to_string(phase)
        })
      end)
    end

    Map.merge(state, %{
      phase: phase,
      operation_span: nil,
      last_status: phase,
      pass_count: Map.get(state, :pass_count, 0) + 1
    })
  end

  defp reply_waiters(state) do
    state = recheck_ready(state)

    if map_size(state.errors) == 0 do
      Enum.each(state.waiters, fn {_, {from, timer}} ->
        if timer, do: Process.cancel_timer(timer)
        GenServer.reply(from, :ok)
      end)

      %{state | phase: :ready, waiters: %{}} |> schedule_reconcile()
    else
      %{state | phase: :degraded} |> schedule_reconcile()
    end
  end

  defp schedule_reconcile(%{repair: :manual} = state), do: state

  defp schedule_reconcile(state) do
    token = make_ref()

    timer =
      Process.send_after(
        self(),
        {:reconcile, token},
        state.instance.definition.startup.retry_interval
      )

    %{state | reconcile_timer: timer, reconcile_token: token}
  end

  defp task_context(key, member, state) do
    if Map.has_key?(state.instance.plan.resources, key) do
      %{jido: state.jido, pool: Controller.name(state.jido, state.instance.id, :resources)}
    else
      bus_ids =
        Map.new(member.subscriptions, fn sub ->
          {sub.bus, Map.fetch!(state.instance.plan.resources, sub.bus).id}
        end)

      %{
        jido: state.jido,
        instance_id: state.instance.id,
        parent: if(member.parent, do: Map.fetch!(state.ready, member.parent)),
        bus_ids: bus_ids,
        retry_interval: state.instance.definition.startup.retry_interval,
        task_timeout: state.instance.definition.startup.task_timeout
      }
    end
  end

  defp ensure(%{kind: _kind} = spec, %{pool: _pool} = context),
    do: Resource.ensure(spec, context)

  defp ensure(spec, context) do
    with {:ok, pid} <- activate(spec, context),
         :ok <- ready_bus_inputs(pid, spec, context),
         :ok <- bind_parent(pid, spec, context),
         do: {:ok, pid}
  end

  defp ready_bus_inputs(_pid, %{subscriptions: []}, _context), do: :ok

  defp ready_bus_inputs(pid, _spec, context) do
    case Map.get(Server.children(pid), {:plugin, BusInputs}) do
      %{pid: runtime} when is_pid(runtime) ->
        BusInputs.await_ready(runtime, timeout: context.task_timeout)

      _missing ->
        {:error, :subscription_unavailable}
    end
  end

  defp activate(spec, context) do
    case whereis_agent(spec, context) do
      nil ->
        start_agent(spec, context)

      pid ->
        if owned?(:agent, pid, spec, context),
          do: {:ok, pid},
          else: {:error, :agent_identity_in_use}
    end
  end

  defp start_agent(spec, context) do
    result =
      if spec.node == node(),
        do: Controller.Activation.start(spec, context),
        else: Controller.Activation.start_on_node(spec, context)

    with {:ok, pid} <- result do
      if owned?(:agent, pid, spec, context) do
        {:ok, pid}
      else
        stop_agent(context.jido, pid, context.task_timeout)
        {:error, :restored_agent_identity_in_use}
      end
    end
  end

  defp placement_target(state, target, member) do
    key = Plan.resolve(state.instance.plan, target, :agent, member)

    case agent_spec(key, state) do
      nil -> Jido.Agent.Authoring.error("Unknown topology Agent placement target")
      spec -> {:ok, key, spec}
    end
  end

  defp placement_node(value) when is_atom(value) and value not in [nil, true, false], do: :ok

  defp placement_node(_value),
    do: Jido.Agent.Authoring.error("Topology Agent node must be an atom")

  defp placement_resources(%{subscriptions: []}, _target_node), do: :ok
  defp placement_resources(_spec, target_node) when target_node == node(), do: :ok

  defp placement_resources(_spec, _target_node),
    do: Jido.Agent.Authoring.error("A remote topology Agent cannot subscribe to a local Bus")

  defp retire(%{node: target_node} = spec, state, timeout) do
    context = ownership_context(state)

    with {:ok, pid} <- lookup_agent(spec, state.jido, timeout) do
      cond do
        is_nil(pid) ->
          :ok

        not owned?(:agent, pid, spec, context) ->
          Jido.Agent.Authoring.error("Topology Agent identity is in use")

        true ->
          case stop_agent(state.jido, pid, timeout) do
            :ok -> :ok
            {:error, :not_found} -> :ok
            {:error, reason} -> {:error, {:placement_stop_failed, target_node, reason}}
          end
      end
    end
  end

  defp bind_parent(_pid, %{parent: nil}, _state), do: :ok

  defp bind_parent(pid, spec, %{parent: parent}) do
    case Map.get(Server.children(parent), spec.key) do
      %{pid: ^pid} -> :ok
      nil -> Server.adopt_child(parent, pid, spec.key)
      _ -> {:error, :parent_binding_pending}
    end
  end

  defp marker(spec, instance_id), do: %{id: instance_id, key: spec.key}

  defp ownership_context(state) do
    %{
      jido: state.jido,
      instance_id: state.instance.id,
      pool: Controller.name(state.jido, state.instance.id, :resources),
      ready: state.ready
    }
  end

  defp owned?(kind, pid, spec, context) when is_pid(pid) do
    alive?(pid) and safely(fn -> owns?(kind, pid, spec, context) end) == true
  end

  defp owned?(_kind, _pid, _spec, _context), do: false

  defp owns?(:agent, pid, spec, context) do
    agent = Server.agent(pid)

    agent.module == spec.module and
      Map.get(agent.metadata, "jido.topology") == marker(spec, context.instance_id)
  end

  defp lifecycle_signal(module, topology_id, data) do
    module.new!(Map.put(data, :topology_id, topology_id),
      source: "/jido/topology/" <> URI.encode(topology_id, &URI.char_unreserved?/1)
    )
  end

  defp component_data(operation_id, spec) do
    %{
      operation_id: operation_id,
      component: spec.key,
      kind: Atom.to_string(spec.kind),
      node: Atom.to_string(Map.get(spec, :node) || node())
    }
  end

  defp status(nil), do: nil
  defp status(value), do: Atom.to_string(value)

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_code({reason, _details}) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code(%{__struct__: module}) when is_atom(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp reason_code(_reason), do: "unknown"

  defp refresh_phase(%{phase: :ready} = state) do
    state = recheck_ready(state)
    if map_size(state.errors) == 0, do: state, else: %{state | phase: :degraded}
  end

  defp refresh_phase(state), do: state

  defp recheck_ready(state) do
    Enum.reduce(state.ready, state, fn {key, pid}, acc ->
      if is_pid(pid) and alive?(pid) do
        acc
      else
        %{
          acc
          | ready: Map.delete(acc.ready, key),
            errors: Map.put(acc.errors, key, :member_unavailable)
        }
      end
    end)
  end

  defp intentional_shutdown?(:shutdown), do: true
  defp intentional_shutdown?({:shutdown, _reason}), do: true
  defp intentional_shutdown?(_reason), do: false

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp whereis_agent(%{node: target, id: id}, %{jido: jido}) when target == node(),
    do: Jido.whereis_agent(jido, id)

  defp whereis_agent(%{node: target, id: id}, %{jido: jido}) do
    :erpc.call(target, Jido, :whereis_agent, [jido, id], 1_000)
  catch
    _kind, _reason -> nil
  end

  defp lookup_agent(%{node: target, id: id}, jido, _timeout) when target == node(),
    do: {:ok, Jido.whereis_agent(jido, id)}

  defp lookup_agent(%{node: target, id: id}, jido, timeout) do
    {:ok, :erpc.call(target, Jido, :whereis_agent, [jido, id], timeout)}
  catch
    kind, reason -> {:error, {:placement_uncertain, target, {kind, reason}}}
  end

  defp alive?(pid) when node(pid) == node(), do: Process.alive?(pid)

  defp alive?(pid) do
    :erpc.call(node(pid), Process, :alive?, [pid], 1_000)
  catch
    _kind, _reason -> false
  end

  defp stop_agent(jido, pid, _timeout) when node(pid) == node(), do: Jido.stop_agent(jido, pid)

  defp stop_agent(jido, pid, timeout) do
    :erpc.call(node(pid), Jido, :stop_agent, [jido, pid], timeout)
  catch
    _kind, _reason -> {:error, :remote_stop_uncertain}
  end

  defp emit(state, signal) when is_function(signal, 0) do
    case Map.get(state, :lifecycle) do
      nil -> :ok
      %Jido.Agent.Ref{} = target -> safely(fn -> Jido.cast(state.jido, target, signal.()) end)
      target -> safely(fn -> Server.cast(target, signal.()) end)
    end

    :ok
  end

  defp load_placements(jido, instance) do
    case Jido.RuntimeStore.get(jido, @placement_hive, instance.id) do
      %{definition: definition, placements: placements}
      when definition == instance.definition and is_map(placements) ->
        Map.take(placements, Map.keys(instance.plan.agents))

      _other ->
        %{}
    end
  end

  defp save_placements(_jido, _instance, placements) when map_size(placements) == 0, do: :ok

  defp save_placements(jido, instance, placements) do
    Jido.RuntimeStore.put(jido, @placement_hive, instance.id, %{
      definition: instance.definition,
      placements: placements
    })
  end
end
