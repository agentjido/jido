defmodule Jido.Plugin.Scheduler.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Cancel, Cron, Delivery, Durable, Occurrence, Schedule}
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%Init{} = init) do
    Process.flag(:trap_exit, true)

    runtime = %{
      agent_server: init.agent_server,
      agent_id: init.agent_id,
      partition: init.partition,
      jido: init.jido,
      options: init.options,
      cron_jobs: %{},
      desired_cron: %{},
      last_reconciled_version: nil,
      timers: %{},
      retry_timer: nil,
      retry_token: nil,
      pending_timer: nil,
      delivery_task: nil,
      delivery_timeout: nil,
      last_delivered_job: nil
    }

    {:ok, runtime, {:continue, :reconcile_agent}}
  end

  @impl true
  def handle_continue(:reconcile_agent, runtime) do
    with {:ok, desired} <- current_plugin_state(runtime),
         {:ok, runtime} <- reconcile_cron(runtime, Map.get(desired, :cron, %{})) do
      notify(runtime, {:scheduler_plugin_ready, self()})
      {:noreply, runtime}
    else
      {:error, reason} ->
        {:stop, {:scheduler_boot_failed, reason}, runtime}

      {:error, reason, runtime} ->
        {:stop, {:scheduler_boot_failed, reason}, runtime}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, runtime), do: {:reply, :ok, runtime}

  def handle_call({:directive, %Schedule{} = directive, context}, _from, runtime) do
    signal = scheduled_signal(directive.signal, context)
    token = make_ref()
    timer = Process.send_after(self(), {:deliver, token, signal}, directive.delay_ms)
    {:reply, :ok, %{runtime | timers: Map.put(runtime.timers, token, timer)}}
  end

  def handle_call({:directive, directive, %DirectiveContext{} = context}, _from, runtime)
      when is_struct(directive, Cron) or is_struct(directive, Cancel) do
    if runtime.last_reconciled_version == context.state_version do
      {:reply, :ok, runtime}
    else
      desired = Map.get(context.plugin_state, :cron, %{})

      case reconcile_cron(runtime, desired) do
        {:ok, runtime} ->
          runtime =
            runtime
            |> cancel_reconcile_retry()
            |> Map.put(:last_reconciled_version, context.state_version)

          {:reply, :ok, runtime}

        {:error, reason, runtime} ->
          runtime = schedule_reconcile_retry(runtime, context.state_version)
          {:reply, {:error, reason}, runtime}
      end
    end
  end

  @impl true
  def handle_cast(:pending_changed, runtime), do: {:noreply, schedule_pending(runtime, 0)}

  @impl true
  def handle_info(:deliver_pending, %{delivery_task: nil} = runtime) do
    runtime = %{runtime | pending_timer: nil}

    if Enum.any?(runtime.desired_cron, fn {_job, spec} -> Durable.enabled?(spec) end) do
      timeout = Keyword.get(runtime.options, :delivery_timeout, 5_000)
      agent_server = runtime.agent_server
      previous_job = runtime.last_delivered_job

      task =
        Task.async(fn ->
          Delivery.attempt(agent_server, previous_job, timeout)
        end)

      timer = Process.send_after(self(), {:delivery_timeout, task.ref}, 2 * timeout + 100)
      {:noreply, %{runtime | delivery_task: task, delivery_timeout: timer}}
    else
      {:noreply, runtime}
    end
  end

  def handle_info({ref, {job, _result}}, %{delivery_task: %Task{ref: ref}} = runtime) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_delivery(%{runtime | last_delivered_job: job})}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{delivery_task: %Task{ref: ref}} = runtime
      ),
      do: {:noreply, finish_delivery(runtime)}

  def handle_info({:delivery_timeout, ref}, %{delivery_task: %Task{ref: ref}} = runtime) do
    Task.shutdown(runtime.delivery_task, :brutal_kill)
    {:noreply, finish_delivery(runtime)}
  end

  def handle_info({:delivery_timeout, _ref}, runtime), do: {:noreply, runtime}

  def handle_info({:deliver, token, signal}, runtime) do
    Server.cast(runtime.agent_server, fresh_signal(signal))
    {:noreply, %{runtime | timers: Map.delete(runtime.timers, token)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, runtime) do
    case cron_job_by_ref(runtime.cron_jobs, ref) do
      {job_id, {_spec, _job, ^ref}} ->
        runtime = %{runtime | cron_jobs: Map.delete(runtime.cron_jobs, job_id)}

        case Map.fetch(runtime.desired_cron, job_id) do
          {:ok, spec} ->
            case start_tracked_cron(runtime, job_id, spec) do
              {:ok, runtime} ->
                {:noreply, runtime}

              {:error, restart_reason, runtime} ->
                notify(
                  runtime,
                  {:scheduler_retry_scheduled, job_id, reason, restart_reason}
                )

                {:noreply, schedule_reconcile_retry(runtime, runtime.last_reconciled_version)}
            end

          :error ->
            {:noreply, runtime}
        end

      nil ->
        {:noreply, runtime}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, runtime), do: {:noreply, runtime}

  def handle_info(
        {:retry_reconcile, token, state_version},
        %{retry_token: token} = runtime
      ) do
    runtime = %{runtime | retry_timer: nil, retry_token: nil}

    case reconcile_cron(runtime, runtime.desired_cron) do
      {:ok, runtime} ->
        notify(runtime, {:scheduler_retry_succeeded, state_version})
        {:noreply, %{runtime | last_reconciled_version: state_version}}

      {:error, reason, runtime} ->
        notify(runtime, {:scheduler_retry_failed, state_version, reason})
        {:noreply, schedule_reconcile_retry(runtime, state_version)}
    end
  end

  def handle_info({:retry_reconcile, _token, _state_version}, runtime),
    do: {:noreply, runtime}

  @impl true
  def terminate(_reason, runtime) do
    if runtime.delivery_task, do: Task.shutdown(runtime.delivery_task, :brutal_kill)
    if runtime.pending_timer, do: Process.cancel_timer(runtime.pending_timer)
    if runtime.delivery_timeout, do: Process.cancel_timer(runtime.delivery_timeout)

    Enum.each(runtime.cron_jobs, fn {_id, {_spec, job, ref}} ->
      Process.demonitor(ref, [:flush])
      SchedEx.cancel(job)
    end)

    Enum.each(runtime.timers, fn {_token, timer} -> :erlang.cancel_timer(timer) end)
    _ = cancel_reconcile_retry(runtime)
    :ok
  end

  defp current_plugin_state(runtime) do
    case Server.plugin_state(runtime.agent_server, Scheduler, 5_000) do
      {:ok, state} -> {:ok, state || %{cron: %{}}}
      {:error, reason} -> {:error, reason}
    end
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end

  defp reconcile_cron(runtime, desired) when is_map(desired) do
    desired = Map.new(desired, fn {job, spec} -> {job, Durable.definition(spec)} end)
    runtime = runtime |> stop_changed_jobs(desired) |> Map.put(:desired_cron, desired)

    Enum.reduce_while(desired, {:ok, runtime}, fn {job_id, spec}, {:ok, runtime} ->
      case ensure_cron_job(runtime, job_id, spec) do
        {:ok, runtime} ->
          {:cont, {:ok, runtime}}

        {:error, reason, runtime} ->
          {:halt, {:error, {:cron_activation_failed, job_id, reason}, runtime}}
      end
    end)
    |> case do
      {:ok, runtime} -> {:ok, schedule_pending(runtime, 0)}
      error -> error
    end
  end

  defp ensure_cron_job(runtime, job_id, spec) do
    case Map.get(runtime.cron_jobs, job_id) do
      {^spec, job, _ref} ->
        if Process.alive?(job) do
          {:ok, runtime}
        else
          runtime |> drop_cron_job(job_id) |> start_tracked_cron(job_id, spec)
        end

      nil ->
        start_tracked_cron(runtime, job_id, spec)
    end
  end

  defp schedule_reconcile_retry(runtime, state_version) do
    runtime = cancel_reconcile_retry(runtime)
    token = make_ref()
    delay = Keyword.get(runtime.options, :retry_delay_ms, 1_000)
    timer = Process.send_after(self(), {:retry_reconcile, token, state_version}, delay)
    %{runtime | retry_timer: timer, retry_token: token}
  end

  defp cancel_reconcile_retry(%{retry_timer: nil} = runtime), do: runtime

  defp cancel_reconcile_retry(runtime) do
    _ = :erlang.cancel_timer(runtime.retry_timer)
    %{runtime | retry_timer: nil, retry_token: nil}
  end

  defp stop_changed_jobs(runtime, desired) do
    jobs =
      Enum.reduce(runtime.cron_jobs, %{}, fn {job_id, {spec, job, ref}}, kept ->
        if Map.get(desired, job_id) == spec do
          Map.put(kept, job_id, {spec, job, ref})
        else
          Process.demonitor(ref, [:flush])
          SchedEx.cancel(job)
          kept
        end
      end)

    %{runtime | cron_jobs: jobs}
  end

  defp start_tracked_cron(runtime, job_id, spec) do
    with {:ok, job} when is_pid(job) <- start_cron(runtime, job_id, spec) do
      tracked = {spec, job, Process.monitor(job)}
      {:ok, %{runtime | cron_jobs: Map.put(runtime.cron_jobs, job_id, tracked)}}
    else
      :ignore -> {:error, :cron_job_not_running, runtime}
      {:error, reason} -> {:error, reason, runtime}
    end
  end

  defp drop_cron_job(runtime, job_id) do
    case Map.pop(runtime.cron_jobs, job_id) do
      {{_spec, _job, ref}, jobs} ->
        Process.demonitor(ref, [:flush])
        %{runtime | cron_jobs: jobs}

      {nil, _jobs} ->
        runtime
    end
  end

  defp cron_job_by_ref(cron_jobs, ref) do
    Enum.find(cron_jobs, fn {_job_id, {_spec, _job, job_ref}} -> job_ref == ref end)
  end

  defp start_cron(runtime, job_id, spec) do
    signal = scheduled_signal(spec.message, nil)

    scope = {runtime.jido, runtime.agent_id, runtime.partition}
    generation = Map.get(spec, :generation)
    options = Keyword.put(Keyword.take(runtime.options, [:time_scale]), :timezone, spec.timezone)

    with :ok <- validate_scope(generation, scope) do
      SchedEx.run_every(
        fn scheduled_at ->
          await_cron_slot(scheduled_at, options)
          tick = cron_tick(spec, signal, scope, job_id, generation, scheduled_at)
          Server.cast(runtime.agent_server, tick)
        end,
        spec.cron_expression,
        options
      )
    end
  end

  defp await_cron_slot(time, options) do
    if Keyword.get(options, :time_scale, SchedEx.IdentityTimeScale) == SchedEx.IdentityTimeScale do
      await_wall_clock(time)
    end
  end

  # SchedEx truncates the timer delay to milliseconds. An early callback can
  # cause its next calculation to select the same slot again. Complete this
  # callback only after the real clock reaches the intended slot. Custom time
  # scales retain their own clock and repeat-delivery semantics.
  defp await_wall_clock(time) do
    remaining = DateTime.diff(time, DateTime.utc_now(), :microsecond)

    if remaining > 0 do
      receive do
      after
        div(remaining + 999, 1_000) -> await_wall_clock(time)
      end
    end
  end

  defp cron_tick(%{delivery: :durable}, _signal, _scope, job, generation, time),
    do: Durable.enqueue_signal(job, generation, time)

  defp cron_tick(_spec, signal, _scope, _job, nil, _time), do: fresh_signal(signal)

  defp cron_tick(_spec, signal, scope, job, generation, time) do
    {:ok, tick} = Occurrence.attach(fresh_signal(signal), scope, job, generation, time)
    tick
  end

  defp finish_delivery(runtime) do
    if runtime.delivery_timeout, do: Process.cancel_timer(runtime.delivery_timeout)
    schedule_pending(%{runtime | delivery_task: nil, delivery_timeout: nil}, 100)
  end

  defp schedule_pending(%{delivery_task: nil, pending_timer: nil} = runtime, delay) do
    if Enum.any?(runtime.desired_cron, fn {_job, spec} -> Durable.enabled?(spec) end),
      do: %{runtime | pending_timer: Process.send_after(self(), :deliver_pending, delay)},
      else: runtime
  end

  defp schedule_pending(runtime, _delay), do: runtime

  defp validate_scope(nil, _scope), do: :ok
  defp validate_scope(_generation, scope), do: Scheduler.validate_occurrence_scope(scope)

  defp scheduled_signal(%Signal{} = signal, %DirectiveContext{effective_signal: source}),
    do: propagate(signal, source)

  defp scheduled_signal(%Signal{} = signal, _context), do: signal

  defp propagate(%Signal{} = signal, %Signal{} = source) do
    case TraceContext.propagate_to(signal, source.id) do
      {:ok, traced} -> traced
      {:error, _reason} -> signal
    end
  end

  defp fresh_signal(%Signal{} = signal) do
    signal
    |> Signal.to_map()
    |> Map.delete("id")
    |> Signal.new!()
  end

  defp notify(runtime, message) do
    if pid = Keyword.get(runtime.options, :test), do: send(pid, message)
    :ok
  end
end
