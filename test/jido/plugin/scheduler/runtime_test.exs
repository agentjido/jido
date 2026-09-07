defmodule Jido.Plugin.Scheduler.RuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Runtime
  alias Jido.Signal
  alias Jido.Tracing.{Context, Trace}

  defmodule PastTimeScale do
    @behaviour SchedEx.TimeScale
    @impl true
    def now("Etc/UTC"), do: ~U[2030-01-01 00:00:00Z]
    @impl true
    def speedup, do: 20
  end

  defmodule ZeroTimeScale do
    @behaviour SchedEx.TimeScale
    @impl true
    def now("Etc/UTC"), do: ~U[2030-01-01 00:00:00Z]
    @impl true
    def speedup, do: 0
  end

  defmodule InvalidNowTimeScale do
    @behaviour SchedEx.TimeScale
    @impl true
    def now("Etc/UTC"), do: :not_a_datetime
    @impl true
    def speedup, do: 1
  end

  defmodule FiniteTimeScale do
    @behaviour SchedEx.TimeScale
    @key {__MODULE__, :clock}

    def reset do
      :persistent_term.put(@key, {~U[2030-01-01 00:00:00.100000Z], now_ms()})
    end

    def clear, do: :persistent_term.erase(@key)

    @impl true
    def now(timezone) do
      {base, started_at} = :persistent_term.get(@key)
      elapsed = now_ms() - started_at

      base
      |> DateTime.add(elapsed * speedup(), :millisecond)
      |> DateTime.shift_zone!(timezone)
    end

    @impl true
    def speedup, do: 1_000

    defp now_ms, do: System.monotonic_time(:millisecond)
  end

  test "idle delivery stops polling until pending work changes" do
    durable = Map.merge(spec(), %{delivery: :durable, generation: 1})
    runtime = %{runtime() | desired_cron: %{job: durable}, delivery_cursor: {:after, :previous}}
    assert {:noreply, armed} = Runtime.handle_cast(:pending_changed, runtime)
    {_timer, token, :immediate} = armed.pending_timer
    assert {:noreply, pending} = Runtime.handle_info({:deliver_pending, token}, armed)
    timeout = pending.delivery_timeout
    ref = pending.delivery_task.ref

    assert_receive {:"$gen_call", from, {:plugin_state, Scheduler}}, 1_000
    :gen_statem.reply(from, {:ok, %{cron: %{}}})
    assert_receive {^ref, {:idle, {:after, :previous}}}, 1_000

    assert {:noreply, completed} =
             Runtime.handle_info({ref, {:idle, {:after, :previous}}}, pending)

    try do
      assert completed.delivery_cursor == {:after, :previous}
      assert completed.desired_cron == runtime.desired_cron
      assert completed.delivery_task == nil
      assert completed.delivery_timeout == nil
      assert Process.read_timer(timeout) == false
      assert completed.pending_timer == nil

      assert {:noreply, woken} = Runtime.handle_cast(:pending_changed, completed)
      assert {_timer, wake_token, :immediate} = woken.pending_timer
      assert is_reference(wake_token)
    after
      Runtime.terminate(:normal, completed)
    end
  end

  test "pending changes replace an idle poll and preserve one wake during delivery" do
    durable = Map.merge(spec(), %{delivery: :durable, generation: 1})
    runtime = %{runtime() | desired_cron: %{job: durable}}
    timer = Process.send_after(self(), {:deliver_pending, :old}, 60_000)
    runtime = %{runtime | pending_timer: {timer, :old, :retry}}

    assert {:noreply, woken} = Runtime.handle_cast(:pending_changed, runtime)
    assert Process.read_timer(timer) == false
    assert {_timer, token, :immediate} = woken.pending_timer
    refute token == :old
    assert {:noreply, ^woken} = Runtime.handle_cast(:pending_changed, woken)

    assert {:noreply, active} = Runtime.handle_info({:deliver_pending, token}, woken)
    assert {:noreply, ^active} = Runtime.handle_info({:deliver_pending, token}, active)
    assert {:noreply, wake_once} = Runtime.handle_cast(:pending_changed, active)
    assert {:noreply, ^wake_once} = Runtime.handle_cast(:pending_changed, wake_once)
    assert wake_once.pending_wake

    assert_receive {:"$gen_call", from, {:plugin_state, Scheduler}}, 1_000
    :gen_statem.reply(from, {:ok, %{cron: %{}}})
    ref = active.delivery_task.ref
    assert_receive {^ref, {:idle, :start}}, 1_000
    assert {:noreply, completed} = Runtime.handle_info({ref, {:idle, :start}}, wake_once)

    try do
      assert completed.delivery_task == nil
      refute completed.pending_wake
      assert {_timer, next_token, :immediate} = completed.pending_timer
      assert is_reference(next_token)
    after
      Runtime.terminate(:normal, completed)
    end
  end

  test "reconciliation wakes delivery only when restored state has pending work" do
    durable = durable_spec(1)
    assert {:reply, :ok, idle} = reconcile(runtime(), %{job: durable}, 1)
    assert idle.pending_timer == nil

    pending = Map.put(durable, :pending, Signal.new!("test.pending", %{}, source: "/test"))
    assert {:reply, :ok, restored} = reconcile(idle, %{job: pending}, 2)

    try do
      assert {_timer, token, :immediate} = restored.pending_timer
      assert is_reference(token)
    after
      Runtime.terminate(:normal, restored)
    end
  end

  test "delivery outcomes emit bounded telemetry" do
    handler = "scheduler-delivery-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :scheduler, :delivery],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    task = Task.async(fn -> :unused end)
    assert_receive {ref, :unused} when ref == task.ref
    timer = Process.send_after(self(), :unused_deadline, 60_000)
    runtime = %{runtime() | delivery_task: task, delivery_timeout: timer}

    outcome =
      {:error, {:after, :job}, {:delivery_failed, %{private: String.duplicate("x", 1_000)}}}

    assert {:noreply, completed} = Runtime.handle_info({task.ref, outcome}, runtime)

    assert_receive {:telemetry, [:jido, :scheduler, :delivery], %{count: 1}, metadata}
    assert metadata == %{outcome: :delivery_error}
    Runtime.terminate(:normal, completed)
  end

  test "restored exhausted cron definitions are dormant and other jobs start" do
    exhausted = cron_spec("0 0 0 1 1 * 2029")
    active = cron_spec("0 0 0 2 1 * 2030")
    test_pid = self()

    agent_server =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:plugin_state, Scheduler}} ->
            :gen_statem.reply(from, {:ok, %{cron: %{exhausted: exhausted, active: active}}})
        end
      end)

    scheduler =
      start_supervised!(
        {Runtime,
         %Init{
           agent_server: agent_server,
           agent_id: "restored-agent",
           module: Scheduler,
           options: [time_scale: PastTimeScale, test: test_pid]
         }}
      )

    assert_receive {:scheduler_plugin_ready, ^scheduler}
    restored = :sys.get_state(scheduler)

    refute Map.has_key?(restored.cron_jobs, :exhausted)
    assert restored.dormant_cron == %{exhausted: exhausted}
    assert {_spec, active_job, _monitor, _token} = restored.cron_jobs.active
    assert Process.alive?(active_job)
  end

  test "a finite cron becomes dormant after its last occurrence" do
    FiniteTimeScale.reset()
    on_exit(&FiniteTimeScale.clear/0)
    finite = cron_spec("30 0 0 1 1 * 2030")
    test_pid = self()
    agent_server = spawn(fn -> scheduler_agent(test_pid, %{finite: finite}) end)
    on_exit(fn -> if Process.alive?(agent_server), do: Process.exit(agent_server, :kill) end)

    scheduler =
      start_supervised!(
        {Runtime,
         %Init{
           agent_server: agent_server,
           agent_id: "finite-agent",
           module: Scheduler,
           options: [time_scale: FiniteTimeScale, test: test_pid]
         }}
      )

    assert_receive {:scheduler_plugin_ready, ^scheduler}
    assert_receive {:scheduler_agent_cast, %Signal{type: "test.tick"}}, 1_000
    assert_receive {:scheduler_cron_dormant, :finite}, 1_000
    dormant = :sys.get_state(scheduler)
    assert dormant.cron_jobs == %{}
    assert dormant.dormant_cron == %{finite: finite}
    refute_received {:scheduler_retry_scheduled, :finite, :normal, _reason}

    unrelated = cron_spec("0 0 0 1 1 * 2099")

    context =
      directive_context(dormant, finite.message, %{cron: %{finite: finite, other: unrelated}}, 1)

    assert :ok =
             GenServer.call(scheduler, {:directive, Scheduler.cancel(:unused), context})

    reconciled = :sys.get_state(scheduler)
    assert reconciled.dormant_cron == %{finite: finite}
    assert Map.has_key?(reconciled.cron_jobs, :other)
    refute_received {:scheduler_cron_dormant, :finite}

    changed = cron_spec("0 0 0 1 1 * 2098")
    context = directive_context(reconciled, finite.message, %{cron: %{finite: changed}}, 2)
    assert :ok = GenServer.call(scheduler, {:directive, Scheduler.cancel(:other), context})

    changed_runtime = :sys.get_state(scheduler)
    refute Map.has_key?(changed_runtime.dormant_cron, :finite)
    assert Map.has_key?(changed_runtime.cron_jobs, :finite)

    context = directive_context(changed_runtime, finite.message, %{cron: %{}}, 3)
    assert :ok = GenServer.call(scheduler, {:directive, Scheduler.cancel(:finite), context})
    assert :sys.get_state(scheduler).dormant_cron == %{}
  end

  test "replaced cron tokens reject stale durable work" do
    runtime = runtime()
    first = durable_spec(1)
    assert {:reply, :ok, first_runtime} = reconcile(runtime, %{job: first}, 1)
    {_spec, _job, _ref, old_token} = first_runtime.cron_jobs.job
    second = durable_spec(2)
    assert {:reply, :ok, second_runtime} = reconcile(first_runtime, %{job: second}, 2)

    try do
      assert {:noreply, ^second_runtime} =
               Runtime.handle_info(
                 {:cron_tick, :job, old_token, ~U[2030-01-01 00:00:01Z]},
                 second_runtime
               )

      refute_received {:"$gen_cast", {:signal, _ref, _signal}}

      {_spec, _job, _ref, current_token} = second_runtime.cron_jobs.job

      assert {:noreply, ^second_runtime} =
               Runtime.handle_info(
                 {:cron_tick, :job, current_token, ~U[2030-01-01 00:00:01Z]},
                 second_runtime
               )

      assert_receive {:"$gen_cast", {:signal, _ref, signal}}
      assert signal.type == "jido.scheduler.enqueue"
      assert signal.data.generation == 2

      assert {:reply, :ok, cancelled_runtime} = reconcile(second_runtime, %{}, 3)

      assert {:noreply, ^cancelled_runtime} =
               Runtime.handle_info(
                 {:cron_tick, :job, current_token, ~U[2030-01-01 00:00:02Z]},
                 cancelled_runtime
               )

      refute_received {:"$gen_cast", {:signal, _ref, _signal}}
    after
      Runtime.terminate(:normal, second_runtime)
    end
  end

  test "delayed traces derive from the source Signal instead of process context" do
    Context.clear()
    on_exit(&Context.clear/0)
    source_trace = Trace.new_root()
    local_trace = Trace.new_root()
    source = Signal.new!("test.source", %{}, source: "/test")
    assert {:ok, source} = Trace.put(source, source_trace)
    local = Signal.new!("test.local", %{}, source: "/test")
    assert {:ok, local} = Trace.put(local, local_trace)
    assert :ok = Context.set_from_signal(local)
    delayed = Signal.new!("test.delayed", %{}, source: "/test")
    runtime = runtime()
    context = directive_context(runtime, source, %{cron: %{}}, 1)

    assert {:reply, :ok, armed} =
             Runtime.handle_call(
               {:directive, Scheduler.schedule(0, delayed), context},
               {self(), make_ref()},
               runtime
             )

    assert_receive {:deliver, token, traced}
    assert {:noreply, _runtime} = Runtime.handle_info({:deliver, token, traced}, armed)
    assert_receive {:"$gen_cast", {:signal, _ref, delivered}}
    trace = Trace.get(delivered)
    assert trace.trace_id == source_trace.trace_id
    assert trace.span_id not in [source_trace.span_id, local_trace.span_id]
    assert trace.parent_span_id == source_trace.span_id
    assert trace.causation_id == source.id
  end

  test "invalid time scale results fail before SchedEx arithmetic" do
    for {time_scale, reason} <- [
          {ZeroTimeScale, {:invalid_time_scale_speedup, 0}},
          {InvalidNowTimeScale, {:invalid_time_scale_now, :not_a_datetime}}
        ] do
      runtime = %{
        runtime()
        | options: [time_scale: time_scale, retry_delay_ms: 4_294_967_295]
      }

      assert {:reply, {:error, {:cron_activation_failed, :job, ^reason}}, failed} =
               reconcile(runtime, %{job: spec()}, 1)

      assert failed.cron_jobs == %{}
      assert is_reference(failed.retry_timer)
      Runtime.terminate(:normal, failed)
    end
  end

  test "maximum delivery timer options stay within the runtime timer limit" do
    durable = Map.merge(spec(), %{delivery: :durable, generation: 1})

    runtime = %{
      runtime()
      | desired_cron: %{job: durable},
        options: [delivery_timeout: 2_147_483_597, delivery_interval: 4_294_967_295]
    }

    assert {:noreply, armed} = Runtime.handle_cast(:pending_changed, runtime)
    {_timer, token, :immediate} = armed.pending_timer
    assert {:noreply, active} = Runtime.handle_info({:deliver_pending, token}, armed)
    assert is_integer(Process.read_timer(active.delivery_timeout))
    assert Process.read_timer(active.delivery_timeout) <= 4_294_967_295
    assert_receive {:"$gen_call", _from, {:plugin_state, Scheduler}}, 1_000
    Runtime.terminate(:normal, active)

    outcome = {:error, {:after, :job}, {:delivery_failed, :rejected}}
    task = Task.async(fn -> outcome end)
    assert_receive {ref, ^outcome} when ref == task.ref
    timeout = Process.send_after(self(), :unused_deadline, 60_000)
    runtime = %{runtime | delivery_task: task, delivery_timeout: timeout}
    assert {:noreply, retrying} = Runtime.handle_info({task.ref, outcome}, runtime)
    assert {timer, _token, :retry} = retrying.pending_timer
    assert is_integer(Process.read_timer(timer))
    assert Process.read_timer(timer) <= 4_294_967_295
    Runtime.terminate(:normal, retrying)
  end

  test "reconciliation retains live jobs and replaces dead jobs before their DOWN is handled" do
    runtime = runtime()
    spec = spec()
    assert {:reply, :ok, runtime} = reconcile(runtime, %{live: spec, dead: spec}, 1)
    {^spec, dead, old_ref, _token} = runtime.cron_jobs.dead
    live = runtime.cron_jobs.live
    barrier = Process.monitor(dead)
    Process.exit(dead, :kill)
    assert_receive {:DOWN, ^barrier, :process, ^dead, :killed}, 1_000

    assert {:reply, :ok, runtime} = reconcile(runtime, %{live: spec, dead: spec}, 2)

    try do
      assert runtime.cron_jobs.live == live
      assert {^spec, replacement, new_ref, _token} = runtime.cron_jobs.dead
      assert replacement != dead
      assert new_ref != old_ref
      assert Process.alive?(replacement)
      refute_received {:DOWN, ^old_ref, :process, ^dead, _}

      assert {:noreply, ^runtime} =
               Runtime.handle_info({:DOWN, old_ref, :process, dead, :killed}, runtime)
    after
      Runtime.terminate(:normal, runtime)
    end
  end

  test "an older cancellation dispatch cannot replace newer runtime state" do
    first = spec()
    assert {:reply, :ok, current} = reconcile(runtime(), %{job: first}, 2)
    stale = directive_context(current, first.message, %{cron: %{}}, 1)

    try do
      assert {:reply, :ok, ^current} =
               Runtime.handle_call(
                 {:directive, Scheduler.cancel(:job), stale},
                 {self(), make_ref()},
                 current
               )

      assert Map.has_key?(current.cron_jobs, :job)
    after
      Runtime.terminate(:normal, current)
    end
  end

  test "an older cancellation dispatch cannot replace a newer failed activation" do
    tracked = Map.put(spec(), :generation, 1)
    current = %{runtime() | partition: self()}

    assert {:reply, {:error, {:cron_activation_failed, :job, _reason}}, failed} =
             reconcile(current, %{job: tracked}, 2)

    stale = directive_context(failed, tracked.message, %{cron: %{}}, 1)

    try do
      assert {:reply, :ok, ^failed} =
               Runtime.handle_call(
                 {:directive, Scheduler.cancel(:job), stale},
                 {self(), make_ref()},
                 failed
               )

      assert failed.desired_cron == %{job: tracked}
      assert failed.last_reconciled_version == 2
    after
      Runtime.terminate(:normal, failed)
    end
  end

  test "activation stops at the first error and retains completed jobs and desired state" do
    runtime = %{runtime() | partition: self()}
    plain = spec()
    tracked = Map.put(plain, :generation, 1)
    # Use the map's enumeration order to select the successful and failing jobs.
    desired = %{first: plain, second: plain, third: plain}
    [success, failure, later] = Enum.map(desired, &elem(&1, 0))
    desired = desired |> Map.put(failure, tracked) |> Map.put(later, tracked)

    assert {:reply, {:error, {:cron_activation_failed, ^failure, :non_durable_occurrence_scope}},
            runtime} =
             reconcile(runtime, desired, 1)

    try do
      assert Map.keys(runtime.cron_jobs) == [success]
      assert runtime.desired_cron == desired
      assert runtime.last_reconciled_version == 1
      assert is_reference(runtime.retry_timer)
      {^plain, job, _ref, _token} = runtime.cron_jobs[success]
      assert Process.alive?(job)
    after
      Runtime.terminate(:normal, runtime)
    end
  end

  test "a dead matching job is removed when its replacement cannot start" do
    runtime = runtime()
    spec = Map.put(spec(), :generation, 1)
    assert {:reply, :ok, runtime} = reconcile(runtime, %{job: spec}, 1)
    {^spec, job, ref, _token} = runtime.cron_jobs.job
    barrier = Process.monitor(job)
    Process.exit(job, :kill)
    assert_receive {:DOWN, ^barrier, :process, ^job, :killed}, 1_000

    assert {:reply, {:error, {:cron_activation_failed, :job, :non_durable_occurrence_scope}},
            runtime} =
             reconcile(%{runtime | partition: self()}, %{job: spec}, 2)

    try do
      assert runtime.cron_jobs == %{}
      assert runtime.desired_cron == %{job: spec}
      assert runtime.last_reconciled_version == 2
      refute_received {:DOWN, ^ref, :process, ^job, _}
    after
      Runtime.terminate(:normal, runtime)
    end
  end

  defp runtime do
    {:ok, runtime, {:continue, :reconcile_agent}} =
      Runtime.init(%Init{
        agent_server: self(),
        agent_id: "scheduler-contract",
        module: Scheduler,
        options: [retry_delay_ms: 60_000]
      })

    runtime
  end

  test "failed cron restarts retry until the occurrence scope is valid" do
    runtime = %{runtime() | options: [retry_delay_ms: 60_000, test: self()]}
    spec = Map.put(spec(), :generation, 1)
    assert {:reply, :ok, runtime} = reconcile(runtime, %{job: spec}, 1)
    {^spec, job, ref, _token} = runtime.cron_jobs.job
    Process.exit(job, :kill)
    assert_receive {:DOWN, ^ref, :process, ^job, :killed}

    assert {:noreply, failed} =
             Runtime.handle_info({:DOWN, ref, :process, job, :killed}, %{
               runtime
               | partition: self()
             })

    assert failed.cron_jobs == %{}
    assert_receive {:scheduler_retry_scheduled, :job, :killed, :non_durable_occurrence_scope}
    assert {:noreply, ^failed} = Runtime.handle_info({:retry_reconcile, make_ref(), 1}, failed)

    Process.cancel_timer(failed.retry_timer)

    assert {:noreply, retrying} =
             Runtime.handle_info({:retry_reconcile, failed.retry_token, 1}, failed)

    assert_receive {:scheduler_retry_failed, 1,
                    {:cron_activation_failed, :job, :non_durable_occurrence_scope}}

    assert retrying.retry_token != failed.retry_token
    Process.cancel_timer(retrying.retry_timer)

    assert {:noreply, recovered} =
             Runtime.handle_info({:retry_reconcile, retrying.retry_token, 1}, %{
               retrying
               | partition: nil
             })

    try do
      assert_receive {:scheduler_retry_succeeded, 1}
      assert recovered.last_reconciled_version == 1
      assert recovered.retry_timer == nil
      assert {^spec, replacement, _ref, _token} = recovered.cron_jobs.job
      assert Process.alive?(replacement)
    after
      Runtime.terminate(:normal, recovered)
    end
  end

  test "delivery timeout and worker death release the active task" do
    for failure <- [:timeout, :down] do
      task =
        Task.async(fn ->
          receive do
            :finish -> :ok
          end
        end)

      timer = Process.send_after(self(), :unused_deadline, 60_000)
      runtime = %{runtime() | delivery_task: task, delivery_timeout: timer}
      assert {:noreply, ^runtime} = Runtime.handle_info({:delivery_timeout, make_ref()}, runtime)

      event =
        if failure == :timeout do
          {:delivery_timeout, task.ref}
        else
          Process.exit(task.pid, :kill)
          assert_receive {:DOWN, ref, :process, pid, :killed}
          assert ref == task.ref
          assert pid == task.pid
          {:DOWN, ref, :process, pid, :killed}
        end

      assert {:noreply, released} = Runtime.handle_info(event, runtime)
      assert released.delivery_task == nil
      assert released.delivery_timeout == nil
      refute Process.alive?(task.pid)
      assert Process.read_timer(timer) == false
      Runtime.terminate(:normal, released)
    end
  end

  defp spec, do: cron_spec("0 0 1 1 *")

  defp cron_spec(expression) do
    Scheduler.build_cron_spec(expression, Signal.new!("test.tick", %{}, source: "/test"))
  end

  defp durable_spec(generation) do
    Scheduler.build_cron_spec(
      "0 0 1 1 *",
      Signal.new!("test.tick", %{}, source: "/test"),
      nil,
      generation,
      :durable
    )
  end

  defp reconcile(runtime, desired, version) do
    signal = spec().message

    context = directive_context(runtime, signal, %{cron: desired}, version)

    Runtime.handle_call(
      {:directive, Scheduler.cancel(:unused), context},
      {self(), make_ref()},
      runtime
    )
  end

  defp directive_context(runtime, signal, plugin_state, version) do
    %DirectiveContext{
      turn_id: "turn",
      agent_id: runtime.agent_id,
      source_signal: signal,
      effective_signal: signal,
      state_version: version,
      plugin_state: plugin_state
    }
  end

  defp scheduler_agent(test_pid, cron) do
    receive do
      {:"$gen_call", from, {:plugin_state, Scheduler}} ->
        :gen_statem.reply(from, {:ok, %{cron: cron}})
        scheduler_agent(test_pid, cron)

      {:"$gen_cast", {:signal, _ref, signal}} ->
        send(test_pid, {:scheduler_agent_cast, signal})
        scheduler_agent(test_pid, cron)
    end
  end
end
