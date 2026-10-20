defmodule Jido.Plugin.Scheduler.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Cancel, Cron, Occurrence, Schedule, WallClock}
  alias Jido.Signal
  alias Jido.Tracing.Trace

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
      dormant_cron: %{},
      desired_cron: %{},
      last_reconciled_version: nil,
      timers: %{},
      retry_timer: nil,
      retry_token: nil
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
    if stale_state_version?(runtime.last_reconciled_version, context.state_version) do
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
          runtime =
            runtime
            |> Map.put(:last_reconciled_version, context.state_version)
            |> schedule_reconcile_retry(context.state_version)

          {:reply, {:error, reason}, runtime}
      end
    end
  end

  @impl true
  def handle_info({:deliver, token, signal}, runtime) do
    case Map.pop(runtime.timers, token) do
      {nil, _timers} ->
        {:noreply, runtime}

      {_timer, timers} ->
        Server.cast(runtime.agent_server, fresh_signal(signal))
        {:noreply, %{runtime | timers: timers}}
    end
  end

  def handle_info({:cron_tick, job_id, token, scheduled_at}, runtime) do
    with {spec, _job, _ref, ^token} <- Map.get(runtime.cron_jobs, job_id) do
      scope = {runtime.jido, runtime.agent_id, runtime.partition}
      generation = Map.get(spec, :generation)
      tick = cron_tick(spec, spec.message, scope, job_id, generation, scheduled_at)
      Server.cast(runtime.agent_server, tick)
    end

    {:noreply, runtime}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, runtime) do
    case cron_job_by_ref(runtime.cron_jobs, ref) do
      {job_id, {tracked_spec, _job, ^ref, _token}} ->
        runtime = %{runtime | cron_jobs: Map.delete(runtime.cron_jobs, job_id)}
        handle_cron_down(runtime, job_id, tracked_spec, reason)

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
    Enum.each(runtime.cron_jobs, fn {_id, {_spec, job, ref, _token}} ->
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
    runtime = runtime |> stop_changed_jobs(desired) |> Map.put(:desired_cron, desired)

    Enum.reduce_while(desired, {:ok, runtime}, fn {job_id, spec}, {:ok, runtime} ->
      case ensure_cron_job(runtime, job_id, spec) do
        {:ok, runtime} ->
          {:cont, {:ok, runtime}}

        {:error, reason, runtime} ->
          {:halt, {:error, {:cron_activation_failed, job_id, reason}, runtime}}
      end
    end)
  end

  defp ensure_cron_job(runtime, job_id, spec) do
    case {Map.get(runtime.dormant_cron, job_id), Map.get(runtime.cron_jobs, job_id)} do
      {^spec, _tracked} ->
        {:ok, runtime}

      {_dormant, {^spec, job, _ref, _token}} ->
        ensure_live_cron(runtime, job_id, spec, job)

      {_dormant, nil} ->
        start_tracked_cron(runtime, job_id, spec)
    end
  end

  defp ensure_live_cron(runtime, job_id, spec, job) do
    if Process.alive?(job),
      do: {:ok, runtime},
      else: runtime |> drop_cron_job(job_id) |> start_tracked_cron(job_id, spec)
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
      Enum.reduce(runtime.cron_jobs, %{}, fn
        {job_id, {spec, _job, _ref, _token} = tracked}, kept_jobs ->
          if Map.get(desired, job_id) == spec do
            Map.put(kept_jobs, job_id, tracked)
          else
            cancel_tracked_cron(tracked)
            kept_jobs
          end
      end)

    dormant =
      Map.filter(runtime.dormant_cron, fn {job_id, spec} -> Map.get(desired, job_id) == spec end)

    %{runtime | cron_jobs: jobs, dormant_cron: dormant}
  end

  defp start_tracked_cron(runtime, job_id, spec) do
    token = make_ref()

    case start_cron(runtime, job_id, spec, token) do
      {:ok, job} when is_pid(job) ->
        tracked = {spec, job, Process.monitor(job), token}

        {:ok,
         %{
           runtime
           | cron_jobs: Map.put(runtime.cron_jobs, job_id, tracked),
             dormant_cron: Map.delete(runtime.dormant_cron, job_id)
         }}

      :ignore ->
        notify(runtime, {:scheduler_cron_dormant, job_id})
        {:ok, %{runtime | dormant_cron: Map.put(runtime.dormant_cron, job_id, spec)}}

      {:error, reason} ->
        {:error, reason, runtime}
    end
  end

  defp drop_cron_job(runtime, job_id) do
    case Map.pop(runtime.cron_jobs, job_id) do
      {{_spec, _job, ref, _token}, jobs} ->
        Process.demonitor(ref, [:flush])
        %{runtime | cron_jobs: jobs}

      {nil, _jobs} ->
        runtime
    end
  end

  defp cron_job_by_ref(cron_jobs, ref) do
    Enum.find(cron_jobs, fn {_job_id, {_spec, _job, job_ref, _token}} -> job_ref == ref end)
  end

  defp cancel_tracked_cron({_spec, job, ref, _token}) do
    Process.demonitor(ref, [:flush])
    SchedEx.cancel(job)
  end

  defp start_cron(runtime, job_id, spec, token) do
    scope = {runtime.jido, runtime.agent_id, runtime.partition}
    generation = Map.get(spec, :generation)
    options = Keyword.put(Keyword.take(runtime.options, [:time_scale]), :timezone, spec.timezone)
    runtime_pid = self()
    time_scale = Keyword.get(options, :time_scale, SchedEx.IdentityTimeScale)

    with :ok <- validate_scope(generation, scope),
         :ok <- validate_time_scale_runtime(time_scale, spec.timezone) do
      SchedEx.run_every(
        fn scheduled_at ->
          scheduled_at
          |> await_cron_slot(options)
          |> deliver_cron_tick(runtime_pid, job_id, token, scheduled_at)
        end,
        spec.cron_expression,
        options
      )
    end
  end

  defp await_cron_slot(time, options) do
    if Keyword.get(options, :time_scale, SchedEx.IdentityTimeScale) == SchedEx.IdentityTimeScale do
      WallClock.wait_until(time)
    else
      :ok
    end
  end

  defp deliver_cron_tick(:ok, runtime, job_id, token, scheduled_at),
    do: send(runtime, {:cron_tick, job_id, token, scheduled_at})

  defp deliver_cron_tick(:cancelled, _runtime, _job_id, _token, _scheduled_at),
    do: exit(:normal)

  defp handle_cron_down(runtime, job_id, tracked_spec, reason) do
    case {reason, Map.fetch(runtime.desired_cron, job_id)} do
      {:normal, {:ok, ^tracked_spec}} ->
        notify(runtime, {:scheduler_cron_dormant, job_id})

        {:noreply, %{runtime | dormant_cron: Map.put(runtime.dormant_cron, job_id, tracked_spec)}}

      {_reason, {:ok, spec}} ->
        restart_cron(runtime, job_id, spec, reason)

      {_reason, :error} ->
        {:noreply, runtime}
    end
  end

  defp restart_cron(runtime, job_id, spec, reason) do
    case start_tracked_cron(runtime, job_id, spec) do
      {:ok, runtime} ->
        {:noreply, runtime}

      {:error, restart_reason, runtime} ->
        notify(runtime, {:scheduler_retry_scheduled, job_id, reason, restart_reason})
        {:noreply, schedule_reconcile_retry(runtime, runtime.last_reconciled_version)}
    end
  end

  defp cron_tick(_spec, signal, _scope, _job, nil, _time), do: fresh_signal(signal)

  defp cron_tick(_spec, signal, scope, job, generation, time) do
    {:ok, tick} = Occurrence.attach(fresh_signal(signal), scope, job, generation, time)
    tick
  end

  defp validate_scope(nil, _scope), do: :ok
  defp validate_scope(_generation, scope), do: Scheduler.validate_occurrence_scope(scope)

  defp validate_time_scale_runtime(time_scale, timezone) do
    with {:ok, speedup} <- time_scale_call(:speedup, &time_scale.speedup/0),
         :ok <- validate_time_scale_speedup(speedup),
         {:ok, now} <- time_scale_call(:now, fn -> time_scale.now(timezone) end) do
      validate_time_scale_now(now)
    end
  end

  defp validate_time_scale_speedup(speedup) when is_number(speedup) and speedup > 0, do: :ok
  defp validate_time_scale_speedup(speedup), do: {:error, {:invalid_time_scale_speedup, speedup}}

  defp validate_time_scale_now(%DateTime{}), do: :ok
  defp validate_time_scale_now(now), do: {:error, {:invalid_time_scale_now, now}}

  defp time_scale_call(callback, fun) do
    {:ok, fun.()}
  rescue
    error -> {:error, {:time_scale_unavailable, callback, {:error, error}}}
  catch
    kind, reason -> {:error, {:time_scale_unavailable, callback, {kind, reason}}}
  end

  defp scheduled_signal(%Signal{} = signal, %DirectiveContext{effective_signal: source}),
    do: propagate(signal, source)

  defp scheduled_signal(%Signal{} = signal, _context), do: signal

  defp propagate(%Signal{} = signal, %Signal{} = source) do
    case Trace.get(source) do
      %{trace_id: _trace_id, span_id: _span_id} = trace ->
        case Trace.put(signal, Trace.child_of(trace, source.id)) do
          {:ok, traced} -> traced
          {:error, _reason} -> signal
        end

      _trace ->
        signal
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

  defp stale_state_version?(nil, _incoming), do: false

  defp stale_state_version?(last, incoming)
       when is_integer(last) and is_integer(incoming),
       do: incoming <= last
end
