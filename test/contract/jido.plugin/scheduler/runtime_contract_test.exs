defmodule JidoTest.Contract.PluginSchedulerRuntimeTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.plugin.scheduler", async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Runtime
  alias Jido.Signal
  alias Jido.Tracing.{Context, Trace}
  alias JidoTest.ScheduledOccurrenceFixtures.{Clock, FastRuntimeAgent, TimedAgent}

  @instant ~U[2030-01-01 00:00:01Z]

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

  defmodule RaisingTimeScale do
    def now(_timezone), do: ~U[2030-01-01 00:00:00Z]
    def speedup, do: raise("clock unavailable")
  end

  defmodule ThrowingTimeScale do
    def now(_timezone), do: throw(:clock_unavailable)
    def speedup, do: 1
  end

  setup do
    start_supervised!({Clock, []})
    :ok
  end

  defp tick(type \\ "test.tick"), do: Signal.new!(type, %{value: 7}, source: "/test")

  defp runtime(options \\ []) do
    options = Keyword.merge([retry_delay_ms: 60_000], options)

    {:ok, runtime, {:continue, :reconcile_agent}} =
      Runtime.init(%Init{
        agent_server: self(),
        agent_id: "scheduler-contract",
        module: Scheduler,
        jido: ExampleJido,
        partition: nil,
        options: options
      })

    runtime
  end

  defp spec(expression \\ "0 0 1 1 *", generation \\ nil) do
    Scheduler.build_cron_spec(expression, tick(), nil, generation)
  end

  defp context(runtime, plugin_state, version, signal \\ tick()) do
    %DirectiveContext{
      turn_id: "turn",
      agent_id: runtime.agent_id,
      source_signal: signal,
      effective_signal: signal,
      state_version: version,
      plugin_state: plugin_state
    }
  end

  defp reconcile(runtime, desired, version) do
    Runtime.handle_call(
      {:directive, Scheduler.cancel(:unused), context(runtime, %{cron: desired}, version)},
      {self(), make_ref()},
      runtime
    )
  end

  defp scheduler_agent(test_pid, cron) do
    receive do
      {:"$gen_call", from, {:plugin_state, Scheduler}} ->
        :gen_statem.reply(from, {:ok, %{cron: cron}})
        scheduler_agent(test_pid, cron)

      {:"$gen_cast", {:turn, _ref, signal, %{}, :infinity, nil}} ->
        send(test_pid, {:scheduler_agent_cast, signal})
        scheduler_agent(test_pid, cron)
    end
  end

  @tag obligation: "jido.plugin.scheduler.I4"
  test "one-shot timers deliver one fresh traced Signal and ignore stale tokens" do
    Context.clear()
    on_exit(&Context.clear/0)
    source_trace = Trace.new_root()
    local_trace = Trace.new_root()
    source = Signal.new!("test.source", %{}, source: "/test")
    {:ok, source} = Trace.put(source, source_trace)
    local = Signal.new!("test.local", %{}, source: "/test")
    {:ok, local} = Trace.put(local, local_trace)
    :ok = Context.put(Trace.get(local))
    delayed = tick("test.delayed")
    runtime = runtime()

    assert {:reply, :ok, armed} =
             Runtime.handle_call(
               {:directive, Scheduler.schedule(0, delayed),
                context(runtime, %{cron: %{}}, 1, source)},
               {self(), make_ref()},
               runtime
             )

    assert_receive {:deliver, token, traced}
    assert {:noreply, delivered_state} = Runtime.handle_info({:deliver, token, traced}, armed)
    assert_receive {:"$gen_cast", {:turn, _ref, delivered, %{}, :infinity, nil}}
    refute delivered.id == delayed.id
    assert delivered.type == delayed.type
    assert delivered.data == delayed.data
    trace = Trace.get(delivered)
    assert trace.trace_id == source_trace.trace_id
    assert trace.span_id not in [source_trace.span_id, local_trace.span_id]
    assert trace.causation_id == source.id

    assert {:noreply, ^delivered_state} =
             Runtime.handle_info({:deliver, token, traced}, delivered_state)

    refute_received {:"$gen_cast", {:turn, _ref, _signal, %{}, :infinity, nil}}
  end

  @tag obligation: ["jido.plugin.scheduler.I4", "jido.plugin.scheduler.I5"]
  test "runtime termination cancels one-shot and recurring timers" do
    runtime = runtime()

    assert {:reply, :ok, armed} =
             Runtime.handle_call(
               {:directive, Scheduler.schedule(60_000, tick()),
                context(runtime, %{cron: %{}}, 1)},
               {self(), make_ref()},
               runtime
             )

    [{_token, timer}] = Map.to_list(armed.timers)
    assert is_integer(Process.read_timer(timer))
    assert :ok = Runtime.terminate(:normal, armed)
    assert Process.read_timer(timer) == false

    assert {:reply, :ok, recurring} = reconcile(runtime, %{job: spec()}, 1)
    {_spec, job, ref, _token} = recurring.cron_jobs.job
    monitor = Process.monitor(job)
    assert :ok = Runtime.terminate(:normal, recurring)
    assert_receive {:DOWN, ^monitor, :process, ^job, _reason}
    refute_received {:DOWN, ^ref, :process, ^job, _reason}
  end

  @tag obligation: ["jido.plugin.scheduler.I5", "jido.plugin.scheduler.I6"]
  test "recurring reconciliation retains equal jobs and fences stale versions and ticks" do
    runtime = runtime()
    first = spec("0 0 1 1 *", 1)

    assert {:ok, %{cron: %{}}} =
             Scheduler.Agent.apply_directives(%{cron: %{job: first}}, [Scheduler.cancel(:job)])

    assert {:reply, :ok, current} = reconcile(runtime, %{job: first}, 2)
    tracked = current.cron_jobs.job
    {_spec, job, _ref, token} = tracked

    assert {:reply, :ok, same} = reconcile(current, %{job: first}, 3)
    assert same.cron_jobs.job == tracked

    stale_context = context(same, %{cron: %{}}, 3)

    assert {:reply, :ok, ^same} =
             Runtime.handle_call(
               {:directive, Scheduler.cancel(:job), stale_context},
               {self(), make_ref()},
               same
             )

    assert {:noreply, ^same} =
             Runtime.handle_info({:cron_tick, :job, make_ref(), @instant}, same)

    refute_received {:"$gen_cast", {:turn, _ref, _signal, %{}, :infinity, nil}}

    assert {:noreply, ^same} = Runtime.handle_info({:cron_tick, :job, token, @instant}, same)
    assert_receive {:"$gen_cast", {:turn, _ref, signal, %{}, :infinity, nil}}
    assert signal.type == "test.tick"
    refute signal.id == first.message.id
    assert {:ok, occurrence} = Scheduler.occurrence(signal)
    assert occurrence.generation == 1

    replacement = %{spec("0 0 1 1 *", 2) | message: tick("test.replaced")}
    old_job_monitor = Process.monitor(job)
    assert {:reply, :ok, replaced} = reconcile(same, %{job: replacement}, 4)
    assert_receive {:DOWN, ^old_job_monitor, :process, ^job, _reason}
    {_spec, replacement_job, _ref, replacement_token} = replaced.cron_jobs.job
    refute replacement_job == job
    refute replacement_token == token

    assert {:reply, :ok, cancelled} = reconcile(replaced, %{}, 5)
    assert cancelled.cron_jobs == %{}
    assert cancelled.desired_cron == %{}
    Runtime.terminate(:normal, cancelled)
  end

  @tag obligation: ["jido.plugin.scheduler.I5", "jido.plugin.scheduler.I6"]
  test "plain recurring ticks stay untagged and use fresh Signal IDs" do
    runtime = runtime()
    plain = spec()
    assert {:reply, :ok, current} = reconcile(runtime, %{plain: plain}, 1)
    {_spec, _job, _ref, token} = current.cron_jobs.plain

    try do
      assert {:noreply, ^current} =
               Runtime.handle_info({:cron_tick, :plain, token, @instant}, current)

      assert_receive {:"$gen_cast", {:turn, _ref, first, %{}, :infinity, nil}}

      assert {:noreply, ^current} =
               Runtime.handle_info({:cron_tick, :plain, token, @instant}, current)

      assert_receive {:"$gen_cast", {:turn, _ref, second, %{}, :infinity, nil}}
      refute first.id == second.id
      assert {:error, :not_found} = Scheduler.occurrence(first)
      assert {:error, :not_found} = Scheduler.occurrence(second)
    after
      Runtime.terminate(:normal, current)
    end
  end

  @tag obligation: "jido.plugin.scheduler.I5"
  test "reconciliation replaces a dead matching job before its DOWN message" do
    runtime = runtime()
    definition = spec()
    assert {:reply, :ok, current} = reconcile(runtime, %{job: definition}, 1)
    {^definition, job, old_ref, _token} = current.cron_jobs.job
    barrier = Process.monitor(job)
    Process.exit(job, :kill)
    assert_receive {:DOWN, ^barrier, :process, ^job, :killed}

    assert {:reply, :ok, replaced} = reconcile(current, %{job: definition}, 2)

    try do
      {^definition, replacement, new_ref, _token} = replaced.cron_jobs.job
      refute replacement == job
      refute new_ref == old_ref
      assert Process.alive?(replacement)
      refute_received {:DOWN, ^old_ref, :process, ^job, _reason}

      assert {:noreply, ^replaced} =
               Runtime.handle_info({:DOWN, old_ref, :process, job, :killed}, replaced)
    after
      Runtime.terminate(:normal, replaced)
    end
  end

  @tag obligation: ["jido.plugin.scheduler.I7", "jido.plugin.scheduler.I9"]
  test "initial reconciliation restores future jobs and keeps exhausted jobs dormant" do
    exhausted = spec("0 0 0 1 1 * 2029")
    active = spec("0 0 0 2 1 * 2030")
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
    assert :ok = Scheduler.Server.await_ready(scheduler, timeout: 100)
    restored = :sys.get_state(scheduler)
    refute Map.has_key?(restored.cron_jobs, :exhausted)
    assert restored.dormant_cron == %{exhausted: exhausted}
    assert {_spec, active_job, _monitor, _token} = restored.cron_jobs.active
    assert Process.alive?(active_job)

    assert {:reply, :ok, retained} =
             reconcile(restored, %{exhausted: exhausted, active: active}, 1)

    assert retained.dormant_cron == %{exhausted: exhausted}
    assert retained.cron_jobs.active == restored.cron_jobs.active

    assert {:reply, :ok, removed} = reconcile(retained, %{active: active}, 2)
    assert removed.dormant_cron == %{}
  end

  @tag obligation: "jido.plugin.scheduler.I7"
  test "Scheduler runtime and cron job replacement restore committed definitions", %{jido: jido} do
    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(jido, FastRuntimeAgent,
        id: unique_id("scheduler-recovery")
      )

    cron = Scheduler.cron(:heartbeat, "* * * * * * *", tick("cron.tick"))

    assert {:ok, _, _} =
             Server.call(
               server,
               signal("runtime.directive", %{event: :scheduled, directive: cron})
             )

    scheduler = JidoTest.AgentServerAssertions.plugin(server, Scheduler)

    {_spec, old_job, _old_ref, _token} =
      eventually(fn -> Map.get(:sys.get_state(scheduler.pid).cron_jobs, :heartbeat) end)

    monitor = Process.monitor(old_job)
    Process.exit(old_job, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^old_job, :killed}

    new_job =
      eventually(fn ->
        case :sys.get_state(scheduler.pid).cron_jobs.heartbeat do
          {_spec, current, _ref, _token} when current != old_job -> current
          _ -> nil
        end
      end)

    assert Process.alive?(new_job)

    monitor = Process.monitor(scheduler.pid)
    root = Server.activation(server)
    Process.exit(scheduler.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _pid, :killed}
    server = JidoTest.AgentServerAssertions.replacement(root, server)

    replacement =
      eventually(fn ->
        case JidoTest.AgentServerAssertions.plugin(server, Scheduler) do
          %{pid: pid} when pid != scheduler.pid -> pid
          _ -> nil
        end
      end)

    assert Map.has_key?(:sys.get_state(replacement).cron_jobs, :heartbeat)
  end

  @tag obligation: "jido.plugin.scheduler.I7"
  test "Agent restore recreates a future timer with the same generation", %{jido: jido} do
    path = Path.join(System.tmp_dir!(), unique_id("scheduler-restore"))
    on_exit(fn -> File.rm_rf!(path) end)
    persistence = {Jido.Persistence.File, path: path}
    id = unique_id("timed-agent")

    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(jido, TimedAgent,
        id: id,
        persistence: persistence,
        persistence_mode: :create
      )

    {:ok, arm} = TimedAgent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})
    assert {:ok, _, _} = Server.call(server, arm)

    first =
      eventually(fn ->
        case Server.agent(server).state.ticks do
          [tick | _] -> tick
          [] -> nil
        end
      end)

    assert :ok = Server.stop(server)

    {:ok, restored} =
      JidoTest.AgentServerAssertions.start_agent(jido, TimedAgent,
        id: id,
        persistence: persistence,
        persistence_mode: :restore
      )

    runtime = JidoTest.AgentServerAssertions.plugin(restored, Scheduler).pid
    {definition, job, _ref, _token} = :sys.get_state(runtime).cron_jobs["job-1"]
    assert Process.alive?(job)
    assert definition.generation == first.occurrence.generation
  end

  @tag obligation: "jido.plugin.scheduler.I8"
  test "invalid runtime clocks fail activation and own one retry timer" do
    for {time_scale, reason} <- [
          {ZeroTimeScale, {:invalid_time_scale_speedup, 0}},
          {InvalidNowTimeScale, {:invalid_time_scale_now, :not_a_datetime}},
          {RaisingTimeScale,
           {:time_scale_unavailable, :speedup,
            {:error, %RuntimeError{message: "clock unavailable"}}}},
          {ThrowingTimeScale, {:time_scale_unavailable, :now, {:throw, :clock_unavailable}}}
        ] do
      state = %{
        runtime(time_scale: time_scale)
        | options: [time_scale: time_scale, retry_delay_ms: 60_000]
      }

      assert {:reply, {:error, {:cron_activation_failed, :job, ^reason}}, failed} =
               reconcile(state, %{job: spec()}, 1)

      assert failed.cron_jobs == %{}
      assert is_reference(failed.retry_timer)
      assert is_reference(failed.retry_token)

      assert {:reply, :ok, cleared} = reconcile(failed, %{}, 2)
      assert cleared.retry_timer == nil
      assert cleared.retry_token == nil
      assert Process.read_timer(failed.retry_timer) == false
      Runtime.terminate(:normal, cleared)
    end
  end

  @tag obligation: "jido.plugin.scheduler.I8"
  test "failed cron activation retries, ignores stale work, and recovers" do
    runtime = %{runtime(test: self()) | partition: self()}
    tracked = spec("0 0 1 1 *", 1)

    assert {:reply, {:error, {:cron_activation_failed, :job, :nonportable_occurrence_scope}},
            failed} =
             reconcile(runtime, %{job: tracked}, 1)

    assert failed.cron_jobs == %{}
    assert {:noreply, ^failed} = Runtime.handle_info({:retry_reconcile, make_ref(), 1}, failed)

    Process.cancel_timer(failed.retry_timer)

    assert {:noreply, retrying} =
             Runtime.handle_info({:retry_reconcile, failed.retry_token, 1}, failed)

    assert_receive {:scheduler_retry_failed, 1,
                    {:cron_activation_failed, :job, :nonportable_occurrence_scope}}

    Process.cancel_timer(retrying.retry_timer)

    assert {:noreply, recovered} =
             Runtime.handle_info(
               {:retry_reconcile, retrying.retry_token, 1},
               %{retrying | partition: nil}
             )

    try do
      assert_receive {:scheduler_retry_succeeded, 1}
      assert recovered.retry_timer == nil
      assert recovered.retry_token == nil
      assert {^tracked, job, _ref, _token} = recovered.cron_jobs.job
      assert Process.alive?(job)
    after
      Runtime.terminate(:normal, recovered)
    end
  end

  @tag obligation: ["jido.plugin.scheduler.I8", "jido.plugin.scheduler.I9"]
  test "startup preserves state failures and server calls contain runtime loss" do
    {agent_server, monitor} =
      spawn_monitor(fn ->
        receive do
          {:"$gen_call", from, {:plugin_state, Scheduler}} ->
            :gen_statem.reply(from, {:error, :state_unavailable})
        end
      end)

    state = %{runtime() | agent_server: agent_server}

    assert {:stop, {:scheduler_boot_failed, :state_unavailable}, ^state} =
             Runtime.handle_continue(:reconcile_agent, state)

    assert_receive {:DOWN, ^monitor, :process, ^agent_server, :normal}

    assert {:stop, {:scheduler_boot_failed, {:agent_server_unavailable, _reason}}, ^state} =
             Runtime.handle_continue(:reconcile_agent, state)

    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _reason}

    assert {:error, {:scheduler_runtime_unavailable, _reason}} =
             Scheduler.Server.await_ready(dead, timeout: 10)

    assert {:error, {:scheduler_runtime_unavailable, _reason}} =
             Scheduler.Server.dispatch(
               dead,
               Scheduler.cancel(:job),
               context(runtime(), %{cron: %{}}, 1),
               timeout: 10
             )
  end

  @tag obligation: "jido.plugin.scheduler.I9"
  test "the Plugin declares one runtime child and reports readiness after reconciliation" do
    test_pid = self()
    agent_server = spawn(fn -> scheduler_agent(test_pid, %{}) end)

    init = %Init{
      agent_server: agent_server,
      agent_id: "ready-agent",
      module: Scheduler,
      options: [test: self()]
    }

    spec = Scheduler.child_spec(init)
    assert spec.id == Scheduler
    assert spec.start == {Runtime, :start_link, [init]}
    assert runtime().desired_cron == %{}
    scheduler = start_supervised!(spec)
    assert_receive {:scheduler_plugin_ready, ^scheduler}
    assert :ok = Scheduler.await_ready(scheduler, timeout: 100)
  end

  @tag obligation: ["jido.plugin.scheduler.I7", "jido.plugin.scheduler.I8"]
  test "job exits become dormant, disappear, or retry from the latest definition" do
    definition = spec("0 0 1 1 *", 1)
    assert {:reply, :ok, active} = reconcile(runtime(test: self()), %{job: definition}, 1)
    {^definition, job, ref, _token} = active.cron_jobs.job

    assert {:noreply, dormant} =
             Runtime.handle_info({:DOWN, ref, :process, job, :normal}, active)

    assert dormant.cron_jobs == %{}
    assert dormant.dormant_cron == %{job: definition}
    SchedEx.cancel(job)

    assert {:reply, :ok, active} = reconcile(runtime(), %{job: definition}, 1)
    {^definition, job, ref, _token} = active.cron_jobs.job
    removed = %{active | desired_cron: %{}}

    assert {:noreply, gone} =
             Runtime.handle_info({:DOWN, ref, :process, job, :killed}, removed)

    assert gone.cron_jobs == %{}
    SchedEx.cancel(job)

    assert {:reply, :ok, active} = reconcile(runtime(test: self()), %{job: definition}, 1)
    {^definition, job, ref, _token} = active.cron_jobs.job
    broken = %{active | partition: self()}

    assert {:noreply, retrying} =
             Runtime.handle_info({:DOWN, ref, :process, job, :killed}, broken)

    assert retrying.cron_jobs == %{}
    assert is_reference(retrying.retry_timer)
    assert_receive {:scheduler_retry_scheduled, :job, :killed, :nonportable_occurrence_scope}
    SchedEx.cancel(job)
    Runtime.terminate(:normal, retrying)
  end
end
