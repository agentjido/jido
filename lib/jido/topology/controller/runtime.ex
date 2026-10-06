defmodule Jido.Topology.Controller.Runtime do
  @moduledoc false
  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Storage
  alias Jido.Telemetry.Topology, as: TopologyTelemetry
  alias Jido.Topology.{BusInputs, Controller, Plan, Resource}
  alias Jido.Topology.Controller.{AgentSupervisor, TargetStore}
  alias Jido.Topology.Controller.Activation

  alias Jido.Topology.Signal.{
    ComponentFailed,
    ComponentReady,
    OperationCompleted,
    OperationStarted,
    StatusChanged
  }

  alias Jido.Tracing.Context, as: TraceContext

  @live_query_timeout 100
  @live_retry_interval 100

  def start_link(
        {jido, instance, repair, lifecycle, owner, activation, checkpoint_owner, parent_gate}
      ),
      do:
        GenServer.start_link(
          __MODULE__,
          {jido, instance, repair, lifecycle, owner, activation, checkpoint_owner, parent_gate}
        )

  @impl true
  def init({jido, instance, repair, lifecycle, owner, activation, checkpoint_owner, parent_gate}) do
    Process.flag(:trap_exit, true)

    with {:ok, accepted, revision, placements, pending_move} <- TargetStore.load(jido, instance) do
      # A killed coordinator cannot cancel its timers or activation tasks.
      # The dedicated pool survives, so retire those tasks before a new pass.
      tasks = Controller.name(jido, instance.id, :tasks)
      Enum.each(Task.Supervisor.children(tasks), &Task.Supervisor.terminate_child(tasks, &1))

      supervisors =
        for role <- [:resources, :agents, :tasks],
            do: GenServer.whereis(Controller.name(jido, instance.id, role))

      Controller.Owner.observe_tree(owner, supervisors)

      state = %{
        jido: jido,
        owner: owner,
        instance: accepted,
        target_revision: revision,
        repair: repair,
        activation: activation,
        checkpoint_owner: checkpoint_owner,
        parent_gate: parent_gate,
        selected: MapSet.new(),
        hibernated: MapSet.new(),
        unavailable: MapSet.new(),
        waking: MapSet.new(),
        lifecycle: lifecycle,
        reconcile_requested: false,
        reconcile_timer: nil,
        reconcile_token: nil,
        ready: %{},
        errors: %{},
        live_errors: %{},
        live_refresh_token: nil,
        waiters: %{},
        wake_waiters: %{},
        call_leases: %{},
        lease_monitors: %{},
        hibernate_uncertain: %{},
        hibernate_monitors: %{},
        hibernate_waiters: [],
        phase: :starting,
        pending: MapSet.new(),
        active: %{},
        pass_count: 0,
        operation_span: nil,
        operation: nil,
        operation_id: nil,
        operation_override: nil,
        last_status: nil,
        placements: placements,
        pending_move: pending_move
      }

      keys = Map.keys(accepted.plan.agents) ++ Map.keys(accepted.plan.resources)

      selected =
        if activation == :eager,
          do: keys,
          else: Enum.filter(keys, &is_pid(replacement(&1, state)))

      state = %{state | selected: MapSet.new(selected)}

      if selected == [],
        do: {:ok, %{state | phase: :ready}},
        else: {:ok, state, {:continue, :reconcile}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:reconcile, state), do: {:noreply, begin_pass(state)}

  @impl true
  def handle_info({:reconcile, token}, %{reconcile_token: token} = state) when not is_nil(token),
    do: {:noreply, request_pass(state)}

  def handle_info({:reconcile, _token}, state), do: {:noreply, state}

  def handle_info({ref, result}, state) when is_reference(ref),
    do: {:noreply, complete(state, ref, result)}

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.hibernate_monitors, ref) do
      {nil, _hibernate_monitors} ->
        handle_other_down(ref, reason, state)

      {key, hibernate_monitors} ->
        state = %{
          state
          | hibernate_monitors: hibernate_monitors,
            hibernate_uncertain: Map.delete(state.hibernate_uncertain, key)
        }

        spec = agent_spec(key, state)
        _ = cleanup_hibernated(spec, state)
        {:noreply, mark_hibernated(state, key)}
    end
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  def handle_info({:task_timeout, ref}, state) do
    case Map.get(state.active, ref) do
      nil ->
        {:noreply, state}

      job ->
        Process.exit(job.task.pid, :kill)
        {:noreply, %{state | active: Map.put(state.active, ref, %{job | timed_out?: true})}}
    end
  end

  def handle_info({:expire_waiter, token}, state) do
    case Map.pop(state.waiters, token) do
      {nil, _} ->
        {:noreply, state}

      {{_from, _timer, :all}, waiters} ->
        {:noreply, %{state | waiters: waiters}}

      {{from, _timer, _scope}, waiters} ->
        GenServer.reply(from, {:error, :activation_timeout})
        {:noreply, %{state | waiters: waiters}}
    end
  end

  def handle_info({:expire_wake, token}, state) do
    case Map.pop(state.wake_waiters, token) do
      {nil, _waiters} ->
        {:noreply, state}

      {waiter, waiters} ->
        reply =
          if waiter.type == :thaw or MapSet.size(waiter.markers) > 0,
            do: {:error, {:indeterminate, :activation_timeout}},
            else: {:error, :activation_timeout}

        GenServer.reply(waiter.from, reply)

        unavailable =
          if match?({:error, {:indeterminate, _reason}}, reply),
            do: MapSet.union(state.unavailable, waiter.scope),
            else: state.unavailable

        {:noreply,
         %{
           state
           | wake_waiters: waiters,
             unavailable: unavailable
         }}
    end
  end

  def handle_info({:refresh_live, token}, %{live_refresh_token: token} = state)
      when not is_nil(token) do
    state = %{state | live_refresh_token: nil} |> refresh_phase()

    {:noreply, reply_waiters(state)}
  end

  def handle_info({:refresh_live, _token}, state), do: {:noreply, state}

  defp handle_other_down(ref, reason, state) do
    case Map.pop(state.lease_monitors, ref) do
      {nil, _lease_monitors} ->
        {:noreply, complete(state, ref, {:error, reason})}

      {lease, lease_monitors} ->
        state = %{state | lease_monitors: lease_monitors}
        {:noreply, state |> release_lease(lease, false) |> process_hibernate_waiters()}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    state = refresh_phase(state)
    errors = Map.merge(state.errors, state.live_errors)

    {:reply,
     %{
       status: current_phase(state),
       repair: state.repair,
       activation: state.activation,
       active_members:
         Enum.count(state.ready, fn {key, _} -> Map.has_key?(state.instance.plan.agents, key) end),
       dormant_members:
         Enum.count(state.instance.plan.agents, fn {key, _} ->
           not MapSet.member?(state.selected, key) and
             not MapSet.member?(state.hibernated, key)
         end),
       hibernated_members: MapSet.size(state.hibernated),
       member_statuses: member_statuses(state, errors),
       agents: map_size(state.instance.plan.agents),
       target_revision: state.target_revision,
       resources: map_size(state.instance.plan.resources),
       ready: map_size(state.ready),
       errors: errors,
       components: state.instance.plan.components,
       active: map_size(state.active),
       pending: MapSet.size(state.pending)
     }, state}
  end

  def handle_call({:activate, target, :ensure}, _from, state) do
    case target_keys(target, state) do
      {:ok, keys} ->
        selected = keys |> MapSet.difference(state.hibernated) |> MapSet.union(state.selected)
        state = refresh_phase(state)

        if selected == state.selected and
             (target_ready?(keys, state) or map_size(state.active) > 0) do
          {:reply, :ok, state}
        else
          {:reply, :ok, request_pass(%{state | selected: selected})}
        end

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:hibernate, target, deadline}, from, state) do
    case hibernate_request(target, state) do
      {:ok, key, spec} ->
        if leased?(state, key) do
          waiter = %{from: from, key: key, spec: spec, deadline: deadline}
          {:noreply, %{state | hibernate_waiters: state.hibernate_waiters ++ [waiter]}}
        else
          {reply, state} = perform_hibernate(key, spec, deadline, state)
          {:reply, reply, state}
        end

      {:already_hibernated, _key} ->
        {:reply, :ok, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:thaw, target, timeout}, from, state),
    do: begin_wake(:thaw, target, timeout, from, state)

  def handle_call({:checkout_for_call, target, timeout}, from, state),
    do: begin_wake(:call, target, timeout, from, state)

  def handle_call({:release_call, lease}, _from, state) do
    state = state |> release_lease(lease, true) |> process_hibernate_waiters()
    {:reply, :ok, state}
  end

  def handle_call({:await_target, target, timeout}, from, state) do
    case target_keys(target, state) do
      {:ok, keys} -> await_scope(keys, timeout, from, state)
      error -> {:reply, error, state}
    end
  end

  def handle_call(:reconcile, _from, state), do: {:reply, :ok, request_pass(state)}

  def handle_call(:target, _from, state), do: {:reply, state.instance, state}

  def handle_call({:add_agent, key, definition, entry_opts}, _from, state) do
    with :ok <- update_idle(state),
         {:ok, target} <- add_agent_target(state.instance, key, definition, entry_opts),
         {:ok, revision} <-
           TargetStore.accept(state.jido, state.target_revision, target, state.placements) do
      state =
        state
        |> Map.put(:instance, target)
        |> Map.put(:target_revision, revision)
        |> Map.put(:operation_override, :update)
        |> request_pass()

      {:reply, :ok, state}
    else
      {:error, {:indeterminate, reason}} = error ->
        {:stop, {:target_write_indeterminate, reason}, error, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:remove_agent, target, timeout}, _from, state) do
    with :ok <- update_idle(state),
         {:ok, key, spec, target} <- remove_agent_target(state.instance, target),
         :ok <- retire(spec, state, timeout),
         {:ok, revision} <-
           TargetStore.accept(state.jido, state.target_revision, target, state.placements) do
      state =
        state
        |> remove_agent_state(key, target, revision)
        |> request_pass()

      {:reply, :ok, state}
    else
      {:error, {:indeterminate, reason}} = error ->
        {:stop, {:target_write_indeterminate, reason}, error, state}

      {:error, _reason} = error ->
        {:reply, error, request_pass(state)}
    end
  end

  def handle_call(
        {:prepare_agent_definition, target, source, candidate, policy, initial_state},
        _from,
        state
      ) do
    with :ok <- preparation_not_accepted(state, target),
         {:ok, key, spec, prepared} <-
           preparation_agent(state, target, candidate, initial_state),
         :ok <- preparation_available(state, key, spec),
         :ok <-
           Storage.prepare_definition(
             state.jido,
             source,
             prepared,
             policy,
             partition: nil,
             checkpoint_owner: state.checkpoint_owner
           ) do
      {:reply, :ok, state}
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:update, target}, _from, state) do
    with :ok <- update_idle(state),
         :ok <- additive_target(state.instance, target),
         {:ok, revision} <-
           TargetStore.accept(state.jido, state.target_revision, target, state.placements) do
      state =
        state
        |> Map.put(:instance, target)
        |> Map.put(:target_revision, revision)
        |> Map.put(:operation_override, :update)
        |> request_pass()

      {:reply, :ok, state}
    else
      {:error, {:indeterminate, reason}} = error ->
        {:stop, {:target_write_indeterminate, reason}, error, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:place_agent, target, member, target_node, timeout}, _from, state) do
    with :ok <- update_idle(state),
         {:ok, key, current} <- placement_target(state, target, member),
         :ok <- placement_node(target_node),
         :ok <- placement_resources(current, target_node),
         :ok <- placement_owner(current, state, timeout) do
      if current.node == target_node do
        {:reply, :ok, state}
      else
        placements = Map.put(state.placements, key, target_node)
        move = %{key: key, from: current.node, to: target_node}

        case TargetStore.accept_placement(
               state.jido,
               state.target_revision,
               state.instance,
               placements,
               move
             ) do
          {:ok, revision} ->
            state =
              state
              |> Map.put(:placements, placements)
              |> Map.put(:pending_move, move)
              |> Map.put(:target_revision, revision)
              |> Map.update!(:ready, &Map.delete(&1, key))
              |> Map.update!(:errors, &Map.delete(&1, key))
              |> Map.put(:operation_override, :place)

            case finish_pending_move(state, timeout) do
              {:ok, state} -> {:reply, :ok, request_pass(state)}
              {:error, reason, state} -> {:reply, {:error, reason}, pending_error(state, reason)}
              {:fatal, reason, state} -> {:stop, reason, {:error, reason}, state}
            end

          {:error, {:indeterminate, reason}} = error ->
            {:stop, {:target_write_indeterminate, reason}, error, state}

          {:error, _reason} = error ->
            {:reply, error, state}
        end
      end
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:await_active, timeout}, from, state),
    do: await_scope(state.selected, timeout, from, state)

  def handle_call({:await_ready, timeout}, from, state),
    do: await_scope(:all, timeout, from, state)

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

  defp await_scope(scope, timeout, from, state) do
    state = refresh_phase(state)

    if scope_ready?(scope, state) do
      {:reply, :ok, state}
    else
      token = make_ref()

      timer =
        if timeout == :infinity,
          do: nil,
          else: Process.send_after(self(), {:expire_waiter, token}, timeout)

      {:noreply,
       %{state | waiters: Map.put(state.waiters, token, {from, timer, scope})}
       |> schedule_live_refresh()}
    end
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

    # Local member shutdown belongs to the instance supervisor. The remote
    # watcher observes that supervisor, not this replaceable coordinator.

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

  defp current_phase(%{phase: :ready, live_errors: live_errors})
       when map_size(live_errors) > 0,
       do: :degraded

  defp current_phase(state), do: state.phase

  defp member_statuses(state, errors) do
    Map.new(state.instance.plan.agents, fn {key, _member} ->
      status =
        cond do
          MapSet.member?(state.unavailable, key) -> :unavailable
          MapSet.member?(state.hibernated, key) -> :hibernated
          Map.has_key?(errors, key) -> :error
          Map.has_key?(state.ready, key) -> :ready
          MapSet.member?(state.selected, key) -> :starting
          true -> :dormant
        end

      {key, status}
    end)
  end

  defp update_idle(state) do
    if map_size(state.active) == 0 and is_nil(state.pending_move) and
         map_size(state.call_leases) == 0 and map_size(state.wake_waiters) == 0 and
         state.hibernate_waiters == [] and map_size(state.hibernate_uncertain) == 0,
       do: :ok,
       else:
         Jido.Agent.Authoring.error("Topology update or placement requires an idle repair pass")
  end

  defp hibernate_request(target, state) do
    key = resolve_agent_key(target, state)

    cond do
      is_nil(key) or not Map.has_key?(state.instance.plan.agents, key) ->
        {:error, :unknown_member}

      MapSet.member?(state.hibernated, key) ->
        {:already_hibernated, key}

      true ->
        with :ok <- hibernate_idle(state),
             [] <- hibernate_blockers(key, state) do
          {:ok, key, agent_spec(key, state)}
        else
          [_ | _] = blockers -> {:error, {:hibernate_blocked, blockers}}
          {:error, _reason} = error -> error
        end
    end
  end

  defp hibernate_idle(state) do
    if map_size(state.active) == 0 and MapSet.size(state.pending) == 0 and
         is_nil(state.pending_move) and state.phase != :starting,
       do: :ok,
       else: Jido.Agent.Authoring.error("Hibernate requires an idle repair pass")
  end

  defp hibernate_blockers(key, state) do
    active_keys = Map.new(state.active, fn {_ref, job} -> {job.key, true} end)

    key
    |> reverse_dependency_closure(state, MapSet.new())
    |> MapSet.delete(key)
    |> Enum.filter(fn dependent ->
      MapSet.member?(state.selected, dependent) or
        MapSet.member?(state.pending, dependent) or
        Map.has_key?(state.ready, dependent) or Map.has_key?(active_keys, dependent)
    end)
    |> Enum.sort()
  end

  defp reverse_dependency_closure(key, state, found) do
    dependents =
      state.instance.plan.agents
      |> Map.merge(state.instance.plan.resources)
      |> Enum.flat_map(fn {candidate, member} ->
        if key in member.depends_on, do: [candidate], else: []
      end)

    Enum.reduce(dependents, MapSet.put(found, key), fn dependent, acc ->
      if MapSet.member?(acc, dependent),
        do: acc,
        else: reverse_dependency_closure(dependent, state, acc)
    end)
  end

  defp perform_hibernate(key, spec, deadline, state) do
    timeout = remaining(deadline)

    if timeout == 0 do
      {{:error, {:indeterminate, :hibernate_timeout}}, state}
    else
      case lookup_agent(spec, state.jido, timeout) do
        {:ok, nil} ->
          {:ok, mark_hibernated(state, key)}

        {:ok, pid} ->
          hibernate_running(key, spec, pid, timeout, state)

        {:error, reason} ->
          {{:error, {:indeterminate, reason}}, state}
      end
    end
  end

  defp hibernate_running(key, spec, pid, timeout, state) do
    context = ownership_context(state)

    if owned?(:agent, pid, spec, context, timeout) do
      monitor = Process.monitor(pid)

      case Server.hibernate(pid, timeout: timeout, topology: true) do
        :ok ->
          Process.demonitor(monitor, [:flush])

          case cleanup_hibernated(spec, state) do
            :ok ->
              {:ok, mark_hibernated(state, key)}

            {:error, reason} ->
              {{:error, {:indeterminate, reason}}, mark_hibernated(state, key)}
          end

        {:error, :timeout} ->
          state = uncertain_hibernate(state, key, spec, pid, monitor)
          {{:error, {:indeterminate, :hibernate_timeout}}, state}

        {:error, {:indeterminate, _reason}} = error ->
          Process.demonitor(monitor, [:flush])
          {error, state}

        {:error, _reason} = error ->
          Process.demonitor(monitor, [:flush])
          {error, state}
      end
    else
      {{:error, :member_unavailable}, state}
    end
  end

  defp cleanup_hibernated(%{node: target, key: key}, state) when target == node() do
    AgentSupervisor.retire(Controller.name(state.jido, state.instance.id, :agents), key)
  end

  defp cleanup_hibernated(_spec, _state), do: :ok

  defp uncertain_hibernate(state, key, spec, pid, monitor) do
    %{
      state
      | unavailable: MapSet.put(state.unavailable, key),
        hibernate_uncertain: Map.put(state.hibernate_uncertain, key, %{pid: pid, spec: spec}),
        hibernate_monitors: Map.put(state.hibernate_monitors, monitor, key)
    }
  end

  defp mark_hibernated(state, key) do
    %{
      state
      | hibernated: MapSet.put(state.hibernated, key),
        unavailable: MapSet.delete(state.unavailable, key),
        waking: MapSet.delete(state.waking, key),
        selected: MapSet.delete(state.selected, key),
        pending: MapSet.delete(state.pending, key),
        ready: Map.delete(state.ready, key),
        errors: Map.delete(state.errors, key),
        live_errors: Map.delete(state.live_errors, key)
    }
    |> refresh_phase()
    |> reply_waiters()
  end

  defp begin_wake(kind, target, timeout, from, state) do
    with {:ok, key, scope} <- wake_target(target, state) do
      state = refresh_phase(state)

      if target_ready?(scope, state) and not MapSet.member?(state.hibernated, key) do
        {reply, state} = wake_success(kind, key, MapSet.new(), from, state)
        {:reply, reply, state}
      else
        token = make_ref()

        timer =
          if timeout == :infinity,
            do: nil,
            else: Process.send_after(self(), {:expire_wake, token}, timeout)

        markers = MapSet.intersection(scope, state.hibernated)

        waiter = %{
          from: from,
          type: kind,
          key: key,
          scope: scope,
          markers: markers,
          timer: timer
        }

        state = %{
          state
          | selected: MapSet.union(state.selected, scope),
            waking: MapSet.union(state.waking, scope),
            unavailable: MapSet.difference(state.unavailable, scope),
            wake_waiters: Map.put(state.wake_waiters, token, waiter)
        }

        {:noreply, state |> request_pass() |> reply_wake_waiters()}
      end
    else
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  defp wake_target(target, state) do
    key = resolve_agent_key(target, state)

    if is_binary(key) and Map.has_key?(state.instance.plan.agents, key),
      do: {:ok, key, dependency_closure(key, state, MapSet.new())},
      else: {:error, :unknown_member}
  end

  defp reply_wake_waiters(state) do
    {waiters, state} =
      Enum.reduce(state.wake_waiters, {%{}, state}, fn {token, waiter}, {waiting, acc} ->
        cond do
          target_ready?(waiter.scope, acc) ->
            if waiter.timer, do: Process.cancel_timer(waiter.timer)
            {reply, acc} = wake_success(waiter.type, waiter.key, waiter.markers, waiter.from, acc)
            GenServer.reply(waiter.from, reply)
            {waiting, acc}

          definite_wake_failure?(waiter, acc) and wake_error(waiter.scope, acc) != nil ->
            if waiter.timer, do: Process.cancel_timer(waiter.timer)
            {error_key, reason} = wake_error(waiter.scope, acc)
            GenServer.reply(waiter.from, {:error, {:thaw_failed, error_key, reason}})

            acc = %{
              acc
              | selected: MapSet.difference(acc.selected, waiter.markers),
                unavailable: MapSet.difference(acc.unavailable, waiter.scope)
            }

            {waiting, acc}

          true ->
            {Map.put(waiting, token, waiter), acc}
        end
      end)

    %{state | wake_waiters: waiters}
    |> settle_waking()
  end

  defp wake_success(:thaw, _key, markers, _from, state) do
    {:ok, clear_wake_markers(state, markers)}
  end

  defp wake_success(:call, key, markers, from, state) do
    pid = Map.fetch!(state.ready, key)
    lease = make_ref()
    owner = elem(from, 0)
    monitor = Process.monitor(owner)

    state =
      state
      |> clear_wake_markers(markers)
      |> Map.update!(:call_leases, &Map.put(&1, lease, %{key: key, monitor: monitor}))
      |> Map.update!(:lease_monitors, &Map.put(&1, monitor, lease))

    {{:ok, pid, lease}, state}
  end

  defp clear_wake_markers(state, markers) do
    %{
      state
      | hibernated: MapSet.difference(state.hibernated, markers),
        unavailable: MapSet.difference(state.unavailable, markers),
        waking: MapSet.difference(state.waking, markers)
    }
  end

  defp wake_finished?(state),
    do:
      state.phase != :starting and map_size(state.active) == 0 and MapSet.size(state.pending) == 0

  defp definite_wake_failure?(waiter, state) do
    wake_finished?(state) and (waiter.type == :thaw or MapSet.size(waiter.markers) > 0)
  end

  defp resolve_agent_key({:group, group, member}, state),
    do: Plan.resolve(state.instance.plan, group, :agent, member)

  defp resolve_agent_key(target, state), do: Plan.resolve(state.instance.plan, target, :agent)

  defp wake_error(scope, state) do
    scope
    |> Enum.sort()
    |> Enum.find_value(fn key ->
      case Map.fetch(state.errors, key) do
        {:ok, reason} -> {key, reason}
        :error -> nil
      end
    end)
  end

  defp settle_waking(state) do
    if wake_finished?(state) do
      Enum.reduce(state.waking, %{state | waking: MapSet.new()}, fn key, acc ->
        cond do
          Map.has_key?(acc.ready, key) ->
            %{
              acc
              | hibernated: MapSet.delete(acc.hibernated, key),
                unavailable: MapSet.delete(acc.unavailable, key)
            }

          MapSet.member?(acc.hibernated, key) ->
            _ = cleanup_hibernated(agent_spec(key, acc), acc)

            %{
              acc
              | selected: MapSet.delete(acc.selected, key),
                unavailable: MapSet.delete(acc.unavailable, key)
            }

          true ->
            %{acc | unavailable: MapSet.delete(acc.unavailable, key)}
        end
      end)
    else
      state
    end
  end

  defp leased?(state, key),
    do: Enum.any?(state.call_leases, fn {_lease, entry} -> entry.key == key end)

  defp release_lease(state, lease, demonitor?) do
    case Map.pop(state.call_leases, lease) do
      {nil, _leases} ->
        state

      {%{monitor: monitor}, leases} ->
        if demonitor?, do: Process.demonitor(monitor, [:flush])

        %{
          state
          | call_leases: leases,
            lease_monitors: Map.delete(state.lease_monitors, monitor)
        }
    end
  end

  defp process_hibernate_waiters(state) do
    {waiting, state} =
      Enum.reduce(state.hibernate_waiters, {[], state}, fn waiter, {waiting, acc} ->
        if leased?(acc, waiter.key) do
          {waiting ++ [waiter], acc}
        else
          {reply, acc} = resume_hibernate(waiter, acc)

          GenServer.reply(waiter.from, reply)
          {waiting, acc}
        end
      end)

    %{state | hibernate_waiters: waiting}
  end

  defp resume_hibernate(waiter, state) do
    cond do
      MapSet.member?(state.hibernated, waiter.key) ->
        {:ok, state}

      hibernate_idle(state) != :ok ->
        {hibernate_idle(state), state}

      hibernate_blockers(waiter.key, state) != [] ->
        {{:error, {:hibernate_blocked, hibernate_blockers(waiter.key, state)}}, state}

      true ->
        perform_hibernate(waiter.key, waiter.spec, waiter.deadline, state)
    end
  end

  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp additive_target(%{id: id} = current, %{id: id} = target) do
    {resources_changed?, removed, changed} = Plan.extension_changes(current.plan, target.plan)

    cond do
      current.definition.children != target.definition.children ->
        Jido.Agent.Authoring.error("Topology update cannot change child runtimes")

      resources_changed? ->
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

  defp add_agent_target(current, key, definition, entry_opts) do
    entry =
      entry_opts
      |> Map.put(:key, key)
      |> Map.put(:definition, definition)

    with {:ok, topology} <-
           Jido.Topology.new(%{current.definition | agents: current.definition.agents ++ [entry]}),
         do: Jido.Topology.instantiate(topology, id: current.id, input: current.input)
  end

  defp preparation_agent(state, target, candidate, initial_state) do
    with {:ok, planned} <-
           add_agent_target(state.instance, target, candidate, %{initial_state: initial_state}),
         key when is_binary(key) <- Plan.resolve(planned.plan, target, :agent),
         spec when not is_nil(spec) <- Map.get(planned.plan.agents, key),
         {:ok, definition} <-
           Activation.definition(spec, %{instance_id: state.instance.id, bus_ids: %{}}),
         {:ok, prepared} <-
           Jido.Agent.instantiate(definition, id: spec.id, state: spec.initial_state) do
      {:ok, key, spec, prepared}
    else
      nil -> Jido.Agent.Authoring.error("Unknown definition preparation target")
      {:error, _reason} = error -> error
    end
  end

  defp preparation_available(state, key, spec) do
    cond do
      MapSet.member?(state.selected, key) ->
        preparation_rejected(:selected)

      Map.has_key?(state.ready, key) ->
        preparation_rejected(:ready)

      MapSet.member?(state.pending, key) or state.phase == :starting ->
        preparation_rejected(:starting)

      map_size(state.active) > 0 or not is_nil(state.pending_move) ->
        preparation_rejected(:repair_active)

      stopped_agent_child?(state, key) ->
        preparation_rejected(:stopped_child)

      live_agent?(state, spec) ->
        preparation_rejected(:live_process)

      true ->
        :ok
    end
  end

  defp preparation_not_accepted(state, target) do
    if is_nil(Plan.resolve(state.instance.plan, target, :agent)),
      do: :ok,
      else: preparation_rejected(:accepted)
  end

  defp preparation_rejected(reason),
    do: {:error, {:definition_preparation_rejected, reason}}

  defp stopped_agent_child?(state, key) do
    state.jido
    |> Controller.name(state.instance.id, :agents)
    |> Supervisor.which_children()
    |> Enum.any?(fn
      {^key, pid, _type, _modules} when pid in [:undefined, :restarting] -> true
      _child -> false
    end)
  end

  defp live_agent?(state, %{node: target, id: id}) when target == node(),
    do: is_pid(Jido.whereis_agent(state.jido, id))

  defp live_agent?(state, %{node: target, id: id}) do
    is_pid(:erpc.call(target, Jido, :whereis_agent, [state.jido, id], @live_query_timeout))
  catch
    _kind, _reason -> true
  end

  defp remove_agent_target(current, target) do
    key = Plan.resolve(current.plan, target, :agent)

    case agent_spec(key, %{instance: current}) do
      %{declaration: declaration, key: ^key} = spec when declaration == key ->
        agents =
          Enum.reject(
            current.definition.agents,
            &(Plan.resolve(current.plan, &1.key, :agent) == key)
          )

        with {:ok, topology} <- Jido.Topology.new(%{current.definition | agents: agents}),
             {:ok, target} <-
               Jido.Topology.instantiate(topology, id: current.id, input: current.input) do
          {:ok, key, spec, target}
        end

      %{declaration: _declaration} ->
        Jido.Agent.Authoring.error("Topology removal requires one root Agent")

      nil ->
        Jido.Agent.Authoring.error("Unknown topology Agent removal target")
    end
  end

  defp remove_agent_state(state, key, target, revision) do
    %{
      state
      | instance: target,
        target_revision: revision,
        selected: MapSet.delete(state.selected, key),
        ready: Map.delete(state.ready, key),
        errors: Map.delete(state.errors, key),
        live_errors: Map.delete(state.live_errors, key),
        pending: MapSet.delete(state.pending, key),
        hibernated: MapSet.delete(state.hibernated, key),
        unavailable: MapSet.delete(state.unavailable, key),
        waking: MapSet.delete(state.waking, key),
        placements: Map.delete(state.placements, key),
        operation_override: :update
    }
  end

  defp request_pass(state) do
    if state.reconcile_timer, do: Process.cancel_timer(state.reconcile_timer)
    state = %{state | reconcile_timer: nil, reconcile_token: nil}

    if map_size(state.active) > 0,
      do: %{state | reconcile_requested: true},
      else: begin_pass(state)
  end

  defp begin_pass(%{pending_move: move} = state) when not is_nil(move) do
    case finish_pending_move(state, state.instance.definition.startup.task_timeout) do
      {:ok, state} -> begin_pass(state)
      {:error, reason, state} -> pending_error(state, reason)
      {:fatal, reason, _state} -> exit(reason)
    end
  end

  defp begin_pass(state) do
    desired =
      if state.activation == :eager,
        do: Map.keys(state.instance.plan.agents) ++ Map.keys(state.instance.plan.resources),
        else: MapSet.to_list(state.selected)

    keys =
      desired
      |> MapSet.new()
      |> MapSet.difference(MapSet.difference(state.hibernated, state.waking))
      |> MapSet.to_list()

    state = %{state | selected: MapSet.new(keys)}

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
        %{state | active: active} |> record(job.key, result) |> drive() |> reply_waiters()
    end
  end

  defp record(state, key, {:ok, pid}) do
    if Map.has_key?(state.instance.plan.agents, key),
      do: Jido.Topology.Controller.Owner.track(state.owner, pid)

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

    state
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
      live_errors: %{},
      pass_count: Map.get(state, :pass_count, 0) + 1
    })
  end

  defp reply_waiters(state) do
    state = refresh_phase(state)

    waiters =
      Enum.reduce(state.waiters, %{}, fn {token, {from, timer, scope} = waiter}, acc ->
        if scope_ready?(scope, state) do
          if timer, do: Process.cancel_timer(timer)
          GenServer.reply(from, :ok)
          acc
        else
          Map.put(acc, token, waiter)
        end
      end)

    state
    |> Map.put(:waiters, waiters)
    |> reply_wake_waiters()
    |> schedule_live_refresh()
    |> schedule_reconcile()
  end

  defp scope_ready?(:all, state), do: current_phase(state) == :ready
  defp scope_ready?(keys, state), do: target_ready?(keys, state)

  defp target_ready?(keys, state) do
    Enum.all?(keys, fn key ->
      Map.has_key?(state.ready, key) and not Map.has_key?(state.errors, key) and
        not Map.has_key?(state.live_errors, key)
    end)
  end

  defp target_keys(:all, state),
    do:
      {:ok,
       MapSet.new(Map.keys(state.instance.plan.agents) ++ Map.keys(state.instance.plan.resources))}

  defp target_keys({:resource, target}, state),
    do: target_closure(Plan.resolve(state.instance.plan, target, :bus), state)

  defp target_keys({:group, group, member}, state),
    do: target_closure(Plan.resolve(state.instance.plan, group, :agent, member), state)

  defp target_keys(target, state),
    do: target_closure(Plan.resolve(state.instance.plan, target, :agent), state)

  defp target_closure(nil, _), do: {:error, :unknown_member}

  defp target_closure(key, state) do
    if Map.has_key?(state.instance.plan.agents, key) or
         Map.has_key?(state.instance.plan.resources, key),
       do: {:ok, dependency_closure(key, state, MapSet.new())},
       else: {:error, :unknown_member}
  end

  defp dependency_closure(key, state, keys) do
    if MapSet.member?(keys, key),
      do: keys,
      else:
        Enum.reduce(
          spec(key, state).depends_on,
          MapSet.put(keys, key),
          &dependency_closure(&1, state, &2)
        )
  end

  defp schedule_reconcile(%{phase: :starting} = state), do: state

  defp schedule_reconcile(%{repair: :manual} = state), do: state

  defp schedule_reconcile(%{reconcile_timer: timer} = state) when not is_nil(timer), do: state

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
      %{
        jido: state.jido,
        pool: Controller.name(state.jido, state.instance.id, :resources),
        parent_gate: Map.get(state, :parent_gate)
      }
    else
      bus_ids =
        Map.new(member.subscriptions, fn sub ->
          {sub.bus, Map.fetch!(state.instance.plan.resources, sub.bus).id}
        end)

      %{
        jido: state.jido,
        instance_id: state.instance.id,
        checkpoint_owner: Map.get(state, :checkpoint_owner),
        owner: state.owner,
        agents: Controller.name(state.jido, state.instance.id, :agents),
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
        BusInputs.Server.await_ready(runtime, timeout: context.task_timeout)

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

  defp retire(%{node: target} = spec, state, _timeout) when target == node() do
    # The supervisor serializes retirement with an in-progress restart.
    AgentSupervisor.retire(Controller.name(state.jido, state.instance.id, :agents), spec.key)
  end

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

  defp placement_owner(spec, state, timeout) do
    context = ownership_context(state)

    with {:ok, pid} <- lookup_agent(spec, state.jido, timeout) do
      if is_nil(pid) or owned?(:agent, pid, spec, context),
        do: :ok,
        else: Jido.Agent.Authoring.error("Topology Agent identity is in use")
    end
  end

  defp finish_pending_move(%{pending_move: %{key: key, from: from}} = state, timeout) do
    spec = state.instance.plan.agents |> Map.fetch!(key) |> Map.put(:node, from)

    with :ok <- retire(spec, state, timeout),
         {:ok, revision} <-
           TargetStore.complete_placement(
             state.jido,
             state.target_revision,
             state.instance,
             state.placements
           ) do
      {:ok, %{state | target_revision: revision, pending_move: nil}}
    else
      {:error, {:indeterminate, reason}} ->
        {:fatal, {:target_write_indeterminate, reason}, state}

      {:error, :conflict} ->
        {:fatal, :target_write_conflict, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp pending_error(state, reason) do
    key = state.pending_move.key

    %{state | phase: :degraded, errors: Map.put(state.errors, key, reason)}
    |> schedule_reconcile()
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
      ready: state.ready,
      agents: Controller.name(state.jido, state.instance.id, :agents)
    }
  end

  defp owned?(kind, pid, spec, context, timeout \\ 5_000)

  defp owned?(kind, pid, spec, context, timeout) when is_pid(pid) do
    alive?(pid, timeout) and safely(fn -> owns?(kind, pid, spec, context, timeout) end) == true
  end

  defp owned?(_kind, _pid, _spec, _context, _timeout), do: false

  defp owns?(:agent, pid, spec, context, timeout) do
    agent = Server.agent(pid, timeout)

    matches_agent?(agent, spec, context.instance_id) and
      (node(pid) != node() or AgentSupervisor.owns?(context.agents, spec.key, pid))
  end

  defp matches_agent?(agent, spec, instance_id) do
    agent.id == spec.id and agent.module == spec.module and
      Map.get(agent.metadata, "jido.topology") == marker(spec, instance_id)
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

  defp refresh_phase(%{phase: :starting} = state), do: state

  defp refresh_phase(state) do
    state = state |> settle_uncertain_hibernates() |> recheck_ready()
    phase = if map_size(state.errors) == 0, do: :ready, else: :degraded
    %{state | phase: phase, live_errors: recheck_live_inputs(state)}
  end

  defp settle_uncertain_hibernates(state) do
    Enum.reduce(state.hibernate_uncertain, state, fn {key, entry}, acc ->
      case safely(fn -> Server.status(entry.pid, @live_query_timeout) end) do
        %{phase: :idle} -> clear_uncertain_hibernate(acc, key)
        {:error, _reason} -> acc
        _other -> acc
      end
    end)
  end

  defp clear_uncertain_hibernate(state, key) do
    {entry, uncertain} = Map.pop(state.hibernate_uncertain, key)

    monitor =
      Enum.find_value(state.hibernate_monitors, fn
        {monitor, ^key} -> monitor
        _other -> nil
      end)

    if monitor, do: Process.demonitor(monitor, [:flush])

    %{
      state
      | unavailable: MapSet.delete(state.unavailable, key),
        hibernate_uncertain: uncertain,
        hibernate_monitors: Map.delete(state.hibernate_monitors, monitor),
        ready: if(entry, do: Map.put(state.ready, key, entry.pid), else: state.ready)
    }
  end

  defp recheck_live_inputs(state) do
    Enum.reduce(state.ready, %{}, fn {key, pid}, errors ->
      case agent_spec(key, state) do
        nil ->
          errors

        spec ->
          case live_input_status(key, pid, spec, state) do
            :ok -> errors
            reason -> Map.put(errors, key, reason)
          end
      end
    end)
  end

  defp live_input_status(key, pid, spec, state) do
    with :ok <- live_agent_identity(pid, spec, state.instance.id),
         :ok <- live_bus_inputs(pid, spec),
         :ok <- live_parent_binding(key, pid, spec, state),
         do: :ok
  end

  defp live_agent_identity(pid, spec, instance_id) do
    case safely(fn -> Server.agent(pid, @live_query_timeout) end) do
      %Jido.Agent{} = agent ->
        if matches_agent?(agent, spec, instance_id), do: :ok, else: :agent_identity_in_use

      _error ->
        :member_unavailable
    end
  end

  defp live_bus_inputs(_pid, %{subscriptions: []}), do: :ok

  defp live_bus_inputs(pid, _spec) do
    case safely(fn -> Server.children(pid, @live_query_timeout) end) do
      %{{:plugin, BusInputs} => %{pid: runtime}} when is_pid(runtime) ->
        case safely(fn ->
               BusInputs.Server.ready_snapshot(runtime, timeout: @live_query_timeout)
             end) do
          :ok -> :ok
          _reason -> :subscription_unavailable
        end

      _other ->
        :subscription_unavailable
    end
  end

  defp live_parent_binding(_key, _pid, %{parent: nil}, _state), do: :ok

  defp live_parent_binding(key, pid, %{parent: parent}, state) do
    parent_spec = agent_spec(parent, state)

    expected_parent =
      Map.get(state.ready, parent) || whereis_agent(parent_spec, %{jido: state.jido})

    case safely(fn -> Server.status(pid, @live_query_timeout) end) do
      %{runtime: %{parent: %{pid: ^expected_parent, tag: ^key}}}
      when is_pid(expected_parent) ->
        case safely(fn -> Server.children(expected_parent, @live_query_timeout) end) do
          %{^key => %{pid: ^pid}} -> :ok
          _other -> :parent_binding_pending
        end

      _other ->
        :parent_binding_pending
    end
  end

  defp schedule_live_refresh(%{live_refresh_token: nil} = state) do
    if map_size(state.waiters) > 0 do
      token = make_ref()
      Process.send_after(self(), {:refresh_live, token}, @live_retry_interval)
      %{state | live_refresh_token: token}
    else
      state
    end
  end

  defp schedule_live_refresh(state), do: state

  defp recheck_ready(state) do
    # A query can observe an OTP replacement without requesting a repair pass.
    # Only process availability errors can be cleared here. Wiring still has
    # to pass the live input checks, and installation errors require repair.
    keys =
      Map.keys(state.ready) ++
        for {key, reason} <- state.errors,
            recoverable_member_error?(reason),
            do: key

    keys = Enum.reject(keys, &MapSet.member?(state.hibernated, &1))

    Enum.reduce(keys, state, fn key, acc ->
      previous = Map.get(acc.ready, key)

      pid =
        if is_pid(previous) and alive?(previous),
          do: previous,
          else: replacement(key, acc)

      if is_pid(pid) do
        %{acc | ready: Map.put(acc.ready, key, pid), errors: Map.delete(acc.errors, key)}
      else
        %{
          acc
          | ready: Map.delete(acc.ready, key),
            errors: Map.put_new(acc.errors, key, :member_unavailable)
        }
      end
    end)
  end

  defp recoverable_member_error?({:member_start_failed, _reason}), do: true
  defp recoverable_member_error?(reason), do: reason in [:member_unavailable, :member_stopped]

  defp replacement(key, state) do
    context = ownership_context(state)

    case agent_spec(key, state) do
      nil ->
        Resource.whereis(Map.fetch!(state.instance.plan.resources, key), context)

      spec ->
        pid = whereis_agent(spec, context)
        if owned?(:agent, pid, spec, context, @live_query_timeout), do: pid
    end
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

  defp alive?(pid), do: alive?(pid, 1_000)

  defp alive?(pid, _timeout) when node(pid) == node(), do: Process.alive?(pid)

  defp alive?(pid, timeout) do
    :erpc.call(node(pid), Process, :alive?, [pid], timeout)
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
end
