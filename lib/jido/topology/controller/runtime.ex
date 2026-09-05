defmodule Jido.Topology.Controller.Runtime do
  @moduledoc false
  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Signal.Bus
  alias Jido.Topology.{BusInputs, Controller, Plan}

  def start_link({jido, instance}), do: GenServer.start_link(__MODULE__, {jido, instance})

  @impl true
  def init({jido, instance}) do
    Process.flag(:trap_exit, true)

    state = %{
      jido: jido,
      instance: instance,
      ready: %{},
      errors: %{},
      waiters: %{},
      phase: :starting,
      pending: MapSet.new(),
      active: %{}
    }

    {:ok, state, {:continue, :reconcile}}
  end

  @impl true
  def handle_continue(:reconcile, state), do: {:noreply, begin_pass(state)}

  @impl true
  def handle_info(:reconcile, state), do: {:noreply, begin_pass(state)}

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
    {:reply,
     %{
       status: current_phase(state),
       agents: map_size(state.instance.plan.agents),
       resources: map_size(state.instance.plan.resources),
       ready: map_size(state.ready),
       errors: state.errors,
       components: state.instance.plan.components,
       active: map_size(state.active),
       pending: MapSet.size(state.pending)
     }, state}
  end

  def handle_call({:await_ready, timeout}, from, state) do
    if current_phase(state) == :ready do
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

    pid =
      case Map.get(state.instance.plan.agents, key) do
        nil -> nil
        spec -> Jido.whereis_agent(state.jido, spec.id)
      end

    {:reply, pid, state}
  end

  def handle_call({:bus, target}, _from, state) do
    key = Plan.resolve(state.instance.plan, target, :bus)

    pid =
      case Map.get(state.instance.plan.resources, key) do
        nil ->
          nil

        spec ->
          case Bus.whereis(spec.id, jido: state.jido) do
            {:ok, pid} -> pid
            _ -> nil
          end
      end

    {:reply, pid, state}
  end

  @impl true
  def terminate(_, state) do
    Enum.each(state.active, fn {_, job} -> Task.shutdown(job.task, :brutal_kill) end)

    state.instance.plan.layers
    |> Enum.reverse()
    |> List.flatten()
    |> Enum.each(fn key ->
      case Map.get(state.instance.plan.agents, key) do
        nil ->
          :ok

        spec ->
          safely(fn ->
            case Jido.whereis_agent(state.jido, spec.id) do
              nil -> :ok
              pid -> if owned?(pid, spec, state.instance.id), do: Jido.stop_agent(state.jido, pid)
            end
          end)
      end
    end)

    :ok
  end

  defp current_phase(%{phase: :ready} = state) do
    if Enum.all?(state.ready, fn {_, pid} -> Process.alive?(pid) end), do: :ready, else: :degraded
  end

  defp current_phase(state), do: state.phase

  defp begin_pass(state) do
    keys = Map.keys(state.instance.plan.agents) ++ Map.keys(state.instance.plan.resources)
    %{state | ready: %{}, errors: %{}, pending: MapSet.new(keys), phase: :starting} |> drive()
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
    do: Map.get(state.instance.plan.agents, key) || Map.fetch!(state.instance.plan.resources, key)

  defp dispatch(key, state) do
    supervisor = Controller.name(state.jido, state.instance.id, :tasks)

    member = spec(key, state)
    context = task_context(key, member, state)

    task =
      Task.Supervisor.async_nolink(supervisor, fn -> safely(fn -> ensure(member, context) end) end)

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

  defp record(state, key, {:ok, pid}), do: %{state | ready: Map.put(state.ready, key, pid)}

  defp record(state, key, {:error, reason}),
    do: %{state | errors: Map.put(state.errors, key, reason)}

  defp finish_pass(state) do
    phase = if map_size(state.errors) == 0, do: :ready, else: :degraded

    if phase == :ready do
      Enum.each(state.waiters, fn {_, {from, timer}} ->
        if timer, do: Process.cancel_timer(timer)
        GenServer.reply(from, :ok)
      end)
    end

    Process.send_after(self(), :reconcile, state.instance.definition.startup.retry_interval)
    %{state | phase: phase, waiters: if(phase == :ready, do: %{}, else: state.waiters)}
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
        retry_interval: state.instance.definition.startup.retry_interval
      }
    end
  end

  defp ensure(spec, %{pool: pool} = context) do
    case Bus.whereis(spec.id, jido: context.jido) do
      {:ok, pid} ->
        if Enum.any?(DynamicSupervisor.which_children(pool), &(elem(&1, 1) == pid)),
          do: {:ok, pid},
          else: {:error, :bus_identity_in_use}

      _ ->
        options = Keyword.merge(spec.config, name: spec.id, jido: context.jido)
        DynamicSupervisor.start_child(pool, {Bus, options})
    end
  end

  defp ensure(spec, context) do
    with {:ok, pid} <- activate(spec, context),
         :ok <- Server.await_ready(pid),
         :ok <- subscriptions_ready(pid, spec),
         :ok <- bind_parent(pid, spec, context),
         do: {:ok, pid}
  end

  defp activate(spec, context) do
    case Jido.whereis_agent(context.jido, spec.id) do
      nil ->
        start_agent(spec, context)

      pid ->
        if owned?(pid, spec, context.instance_id),
          do: {:ok, pid},
          else: {:error, :agent_identity_in_use}
    end
  end

  defp start_agent(spec, context) do
    with {:ok, pid} <- Controller.Activation.start(spec, context) do
      if owned?(pid, spec, context.instance_id) do
        {:ok, pid}
      else
        Jido.stop_agent(context.jido, pid)
        {:error, :restored_agent_identity_in_use}
      end
    end
  end

  defp subscriptions_ready(_pid, %{subscriptions: []}), do: :ok

  defp subscriptions_ready(pid, _spec) do
    case Map.get(Server.children(pid), {:plugin, BusInputs}) do
      %{pid: supervisor} when is_pid(supervisor) -> BusInputs.await_ready(supervisor, [])
      _ -> {:error, :subscriptions_unavailable}
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

  defp owned?(pid, spec, instance_id) do
    agent = Server.agent(pid)

    agent.module == spec.module and
      Map.get(agent.metadata, "jido.topology") == marker(spec, instance_id)
  end

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end
end
