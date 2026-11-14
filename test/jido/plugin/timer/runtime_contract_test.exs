defmodule Jido.Plugin.Timer.RuntimeContractTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.plugin.timer", async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Context, as: PluginContext
  alias Jido.Plugin.Init
  alias Jido.Plugin.Timer
  alias Jido.Plugin.Timer.Every
  alias Jido.Plugin.Timer.Occurrence
  alias Jido.Plugin.Timer.Runtime
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Trace
  alias Jido.Trace.Context
  alias Jido.Test.AgentServer.ScheduledOccurrenceFixtures.{Clock, FastRuntimeAgent, TimedAgent}

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

  defmodule DeliveryAdapter do
    @behaviour Jido.Plugin.Timer.DeliveryAdapter

    @impl true
    def reconcile(context, desired) do
      send(Process.get(:timer_delivery_test), {:adapter_reconcile, context, desired})
      result(:reconcile)
    end

    @impl true
    def schedule(context, delay_ms, signal) do
      send(Process.get(:timer_delivery_test), {:adapter_schedule, context, delay_ms, signal})
      result(:schedule)
    end

    defp result(callback) do
      case Process.get({:timer_delivery_result, callback}, :ok) do
        :raise -> raise "adapter #{callback} failed"
        :throw -> throw({:adapter_failed, callback})
        :exit -> exit({:adapter_failed, callback})
        result -> result
      end
    end
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

  defp reduce_state(state, directives),
    do: Timer.reduce(%{plugin_state: state, directives: directives}, [])

  defp runtime(options \\ []) do
    options = Keyword.merge([retry_delay_ms: 60_000], options)

    {:ok, runtime, {:continue, :reconcile_agent}} =
      Runtime.init(%Init{
        agent_server: self(),
        agent_id: "timer-contract",
        module: Timer,
        jido: ExampleJido,
        partition: nil,
        options: options
      })

    runtime
  end

  defp spec(expression \\ "0 0 1 1 *", generation \\ nil) do
    Jido.Plugin.Timer.CronRules.build_spec(expression, tick(), nil, generation)
  end

  defp interval_spec(interval_ms \\ 60_000, generation \\ 0) do
    Every.build_spec(interval_ms, tick("test.interval"), generation)
  end

  defp context(runtime, plugin_state, version, signal \\ tick()) do
    %PluginContext{
      phase: :directive,
      turn_id: "turn",
      agent_id: runtime.agent_id,
      source_signal: signal,
      effective_signal: signal,
      state_version: version,
      plugin_state: plugin_state
    }
  end

  defp reconcile(runtime, desired, version) do
    reconcile_state(runtime, %{cron: desired}, version)
  end

  defp reconcile_state(runtime, state, version) do
    Runtime.handle_call(
      {:directive, Timer.cancel(:unused), context(runtime, state, version)},
      {self(), make_ref()},
      runtime
    )
  end

  defp timer_agent(test_pid, cron) do
    receive do
      {:"$gen_call", from, {:plugin_state, Timer}} ->
        :gen_statem.reply(from, {:ok, %{cron: cron}})
        timer_agent(test_pid, cron)

      {:"$gen_cast", {:turn, _ref, signal, %{}, :infinity, nil}} ->
        send(test_pid, {:timer_agent_cast, signal})
        timer_agent(test_pid, cron)
    end
  end

  @tag obligation: "jido.plugin.timer.I4"
  test "one-shot timers deliver one fresh traced Signal and ignore stale tokens" do
    Context.clear()
    on_exit(&Context.clear/0)
    source_trace = Trace.new()
    local_trace = Trace.new()
    source = Signal.new!("test.source", %{}, source: "/test")
    {:ok, source} = SignalContext.put_trace(source, source_trace)
    local = Signal.new!("test.local", %{}, source: "/test")
    {:ok, local} = SignalContext.put_trace(local, local_trace)
    :ok = Context.put(SignalContext.get_trace(local))
    delayed = tick("test.delayed")
    runtime = runtime()

    assert {:reply, :ok, armed} =
             Runtime.handle_call(
               {:directive, Timer.schedule(0, delayed), context(runtime, %{cron: %{}}, 1, source)},
               {self(), make_ref()},
               runtime
             )

    assert_receive {:deliver, token, traced}
    assert {:noreply, delivered_state} = Runtime.handle_info({:deliver, token, traced}, armed)
    assert_receive {:"$gen_cast", {:turn, _ref, delivered, %{}, :infinity, nil}}
    refute delivered.id == delayed.id
    assert delivered.type == delayed.type
    assert delivered.data == delayed.data
    trace = SignalContext.get_trace(delivered)
    assert trace.trace_id == source_trace.trace_id
    assert trace.span_id not in [source_trace.span_id, local_trace.span_id]
    assert trace.causation_id == source.id

    assert {:noreply, ^delivered_state} =
             Runtime.handle_info({:deliver, token, traced}, delivered_state)

    refute_received {:"$gen_cast", {:turn, _ref, _signal, %{}, :infinity, nil}}
  end

  @tag obligation: ["jido.plugin.timer.I4", "jido.plugin.timer.I5"]
  test "an external delivery adapter replaces all local delivery timers" do
    Process.put(:timer_delivery_test, self())
    on_exit(fn -> Process.delete(:timer_delivery_test) end)
    runtime = runtime(delivery_adapter: DeliveryAdapter)
    desired = %{job: spec("* * * * *", 7)}

    assert {:reply, :ok, reconciled} = reconcile(runtime, desired, 1)
    assert reconciled.cron_jobs == %{}
    assert reconciled.timers == %{}

    assert_receive {:adapter_reconcile, context, ^desired}
    assert context.agent_id == runtime.agent_id
    assert context.scope == {runtime.jido, runtime.agent_id, runtime.partition}

    delayed = tick("test.external.delayed")

    assert {:reply, :ok, unchanged} =
             Runtime.handle_call(
               {:directive, Timer.schedule(25, delayed), context(runtime, %{cron: desired}, 2)},
               {self(), make_ref()},
               reconciled
             )

    assert unchanged.timers == %{}
    assert unchanged.state_version == 2

    assert_receive {:adapter_schedule, schedule_context, 25, scheduled}
    assert schedule_context.state_version == 2
    assert scheduled.type == delayed.type
    refute_receive {:deliver, _token, _signal}
  end

  @tag obligation: ["jido.plugin.timer.I5", "jido.plugin.timer.I6"]
  test "fixed-delay intervals deliver fresh occurrences and reconcile lifecycle changes" do
    runtime = runtime()
    definition = interval_spec(60_000, 4)
    state = %{cron: %{}, every: %{review: definition}}

    assert {:reply, :ok, active} = reconcile_state(runtime, state, 1)
    assert {^definition, timer, token, scheduled_at} = active.interval_jobs.review
    assert is_integer(Process.read_timer(timer))
    Process.cancel_timer(timer)

    assert {:noreply, ticked} =
             Runtime.handle_info({:interval_tick, :review, token, scheduled_at}, active)

    assert_receive {:"$gen_cast", {:turn, _ref, signal, %{}, :infinity, nil}}
    assert signal.type == "test.interval"
    assert signal.id != definition.message.id
    assert {:ok, occurrence} = Occurrence.from_signal(signal)
    assert occurrence.generation == 4
    assert occurrence.scheduled_at == DateTime.to_iso8601(scheduled_at)

    assert {^definition, next_timer, next_token, next_scheduled_at} =
             ticked.interval_jobs.review

    assert next_token != token
    assert DateTime.compare(next_scheduled_at, scheduled_at) == :gt

    assert {:ok, paused_state} = reduce_state(state, [Timer.pause(:review)])
    assert {:reply, :ok, paused} = reconcile_state(ticked, paused_state, 2)
    assert paused.interval_jobs == %{}
    assert paused.desired_every == %{}
    assert Process.read_timer(next_timer) == false

    assert {:noreply, ^paused} =
             Runtime.handle_info(
               {:interval_tick, :review, next_token, next_scheduled_at},
               paused
             )

    refute_received {:"$gen_cast", {:turn, _ref, _signal, %{}, :infinity, nil}}

    assert {:ok, resumed_state} = reduce_state(paused_state, [Timer.resume(:review)])
    assert resumed_state.every.review.generation == 5
    assert {:reply, :ok, resumed} = reconcile_state(paused, resumed_state, 3)

    assert {%{generation: 5}, resumed_timer, _token, _scheduled_at} =
             resumed.interval_jobs.review

    assert is_integer(Process.read_timer(resumed_timer))

    assert {:ok, cancelled_state} = reduce_state(resumed_state, [Timer.cancel(:review)])
    assert {:reply, :ok, cancelled} = reconcile_state(resumed, cancelled_state, 4)
    assert cancelled.interval_jobs == %{}
    assert cancelled.desired_every == %{}
    assert Process.read_timer(resumed_timer) == false
  end

  @tag obligation: ["jido.plugin.timer.I5", "jido.plugin.timer.I8"]
  test "external delivery rejects fixed-delay intervals" do
    Process.put(:timer_delivery_test, self())
    on_exit(fn -> Process.delete(:timer_delivery_test) end)
    definition = interval_spec()
    state = %{cron: %{}, every: %{review: definition}}

    legacy = runtime(delivery_adapter: DeliveryAdapter)

    assert {:reply, {:error, {:external_reconcile_failed, {:interval_delivery_unsupported, DeliveryAdapter}}}, failed} =
             reconcile_state(legacy, state, 1)

    assert failed.interval_jobs == %{}
    refute_received {:adapter_reconcile, _context, _desired}
  end

  @tag obligation: "jido.plugin.timer.I8"
  test "external reconciliation retries the latest committed definitions" do
    Process.put(:timer_delivery_test, self())
    Process.put({:timer_delivery_result, :reconcile}, {:error, :offline})

    on_exit(fn ->
      Process.delete(:timer_delivery_test)
      Process.delete({:timer_delivery_result, :reconcile})
    end)

    runtime = runtime(delivery_adapter: DeliveryAdapter)
    desired = %{latest: spec("*/5 * * * *", 12)}

    assert {:reply, {:error, {:external_reconcile_failed, :offline}}, failed} =
             reconcile(runtime, desired, 9)

    assert failed.desired_cron == desired
    assert failed.state_version == 9
    assert failed.last_reconciled_version == 9
    assert is_reference(failed.retry_token)
    assert_receive {:adapter_reconcile, first_context, ^desired}
    assert first_context.state_version == 9

    Process.put({:timer_delivery_result, :reconcile}, :ok)
    Process.cancel_timer(failed.retry_timer)

    assert {:noreply, recovered} =
             Runtime.handle_info(
               {:retry_reconcile, failed.retry_token, failed.last_reconciled_version},
               failed
             )

    assert_receive {:adapter_reconcile, retry_context, ^desired}
    assert retry_context.state_version == 9
    assert recovered.desired_cron == desired
    assert recovered.last_reconciled_version == 9
    assert recovered.retry_timer == nil
    assert recovered.retry_token == nil
  end

  @tag obligation: "jido.plugin.timer.I8"
  test "external delayed delivery contains invalid results and adapter failures" do
    Process.put(:timer_delivery_test, self())

    on_exit(fn ->
      Process.delete(:timer_delivery_test)
      Process.delete({:timer_delivery_result, :schedule})
    end)

    runtime = runtime(delivery_adapter: DeliveryAdapter)
    directive = Timer.schedule(25, tick("test.external.failure"))
    directive_context = context(runtime, %{cron: %{}}, 4)

    Process.put({:timer_delivery_result, :schedule}, :invalid)

    assert {:reply, {:error, {:external_schedule_invalid_result, :invalid}}, invalid_state} =
             Runtime.handle_call(
               {:directive, directive, directive_context},
               {self(), make_ref()},
               runtime
             )

    assert invalid_state.timers == %{}
    assert invalid_state.state_version == 4
    assert_receive {:adapter_schedule, _context, 25, _signal}

    Process.put({:timer_delivery_result, :schedule}, :raise)

    assert {:reply, {:error, {:external_schedule_failed, {:adapter_exception, "adapter schedule failed"}}},
            raised_state} =
             Runtime.handle_call(
               {:directive, directive, directive_context},
               {self(), make_ref()},
               invalid_state
             )

    assert raised_state.timers == %{}
    assert_receive {:adapter_schedule, _context, 25, _signal}
  end

  @tag obligation: ["jido.plugin.timer.I4", "jido.plugin.timer.I5"]
  test "runtime termination cancels one-shot and recurring timers" do
    runtime = runtime()

    assert {:reply, :ok, armed} =
             Runtime.handle_call(
               {:directive, Timer.schedule(60_000, tick()), context(runtime, %{cron: %{}}, 1)},
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

  @tag obligation: ["jido.plugin.timer.I5", "jido.plugin.timer.I6"]
  test "recurring reconciliation retains equal jobs and fences stale versions and ticks" do
    runtime = runtime()
    first = spec("0 0 1 1 *", 1)

    assert {:ok, %{cron: %{}}} =
             reduce_state(%{cron: %{job: first}}, [Timer.cancel(:job)])

    assert {:reply, :ok, current} = reconcile(runtime, %{job: first}, 2)
    tracked = current.cron_jobs.job
    {_spec, job, _ref, token} = tracked

    assert {:reply, :ok, same} = reconcile(current, %{job: first}, 3)
    assert same.cron_jobs.job == tracked

    stale_context = context(same, %{cron: %{}}, 3)

    assert {:reply, :ok, ^same} =
             Runtime.handle_call(
               {:directive, Timer.cancel(:job), stale_context},
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
    assert {:ok, occurrence} = Occurrence.from_signal(signal)
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

  @tag obligation: ["jido.plugin.timer.I5", "jido.plugin.timer.I6"]
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
      assert {:error, :not_found} = Occurrence.from_signal(first)
      assert {:error, :not_found} = Occurrence.from_signal(second)
    after
      Runtime.terminate(:normal, current)
    end
  end

  @tag obligation: "jido.plugin.timer.I5"
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

  @tag obligation: ["jido.plugin.timer.I7", "jido.plugin.timer.I9"]
  test "initial reconciliation restores future jobs and keeps exhausted jobs dormant" do
    exhausted = spec("0 0 0 1 1 * 2029")
    active = spec("0 0 0 2 1 * 2030")
    test_pid = self()

    agent_server =
      spawn(fn ->
        receive do
          {:"$gen_call", from, {:plugin_state, Timer}} ->
            :gen_statem.reply(from, {:ok, %{cron: %{exhausted: exhausted, active: active}}})
        end
      end)

    timer =
      start_supervised!(
        {Runtime,
         %Init{
           agent_server: agent_server,
           agent_id: "restored-agent",
           module: Timer,
           options: [time_scale: PastTimeScale, test: test_pid]
         }}
      )

    assert_receive {:timer_plugin_ready, ^timer}
    assert :ok = Timer.await_ready(timer, timeout: 100)
    restored = :sys.get_state(timer)
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

  @tag obligation: "jido.plugin.timer.I7"
  test "Timer runtime and cron job replacement restore committed definitions", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, FastRuntimeAgent, id: unique_id("timer-recovery"))

    cron = Timer.cron(:heartbeat, "* * * * * * *", tick("cron.tick"))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(
               server,
               signal("runtime.directive", %{event: :scheduled, directive: cron})
             )

    timer = Jido.Test.AgentServer.Assertions.plugin(server, Timer)

    {_spec, old_job, _old_ref, _token} =
      eventually(fn -> Map.get(:sys.get_state(timer.pid).cron_jobs, :heartbeat) end)

    monitor = Process.monitor(old_job)
    Process.exit(old_job, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^old_job, :killed}

    new_job =
      eventually(fn ->
        case :sys.get_state(timer.pid).cron_jobs.heartbeat do
          {_spec, current, _ref, _token} when current != old_job -> current
          _ -> nil
        end
      end)

    assert Process.alive?(new_job)

    monitor = Process.monitor(timer.pid)
    root = Jido.Test.AgentServer.Assertions.activation(server)
    Process.exit(timer.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _pid, :killed}
    server = Jido.Test.AgentServer.Assertions.replacement(root, server)

    replacement =
      eventually(fn ->
        case Jido.Test.AgentServer.Assertions.plugin(server, Timer) do
          %{pid: pid} when pid != timer.pid -> pid
          _ -> nil
        end
      end)

    assert Map.has_key?(:sys.get_state(replacement).cron_jobs, :heartbeat)
  end

  @tag obligation: ["jido.plugin.timer.I5", "jido.plugin.timer.I6"]
  test "managed interval schedules deliver repeated Agent Signals", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, FastRuntimeAgent, id: unique_id("timer-interval-delivery"))

    every = Timer.every(:heartbeat, 25, tick("cron.tick"))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(
               server,
               signal("runtime.directive", %{event: :scheduled, directive: every})
             )

    eventually(fn -> Server.snapshot(server).agent.state.ticks >= 2 end)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(
               server,
               signal("runtime.directive", %{
                 event: :paused,
                 directive: Timer.pause(:heartbeat)
               })
             )

    paused_ticks = Server.snapshot(server).agent.state.ticks
    Process.sleep(75)
    assert Server.snapshot(server).agent.state.ticks == paused_ticks
  end

  @tag obligation: "jido.plugin.timer.I7"
  test "Timer runtime replacement restores active intervals and preserves pause", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, FastRuntimeAgent, id: unique_id("timer-interval-recovery"))

    every = Timer.every(:review, 60_000, tick("runtime.record"))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(
               server,
               signal("runtime.directive", %{event: :scheduled, directive: every})
             )

    timer_plugin = Jido.Test.AgentServer.Assertions.plugin(server, Timer)

    assert {_spec, tracked_timer, _token, _scheduled_at} =
             eventually(fn -> Map.get(:sys.get_state(timer_plugin.pid).interval_jobs, :review) end)

    assert is_integer(Process.read_timer(tracked_timer))
    monitor = Process.monitor(timer_plugin.pid)
    root = Jido.Test.AgentServer.Assertions.activation(server)
    Process.exit(timer_plugin.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _pid, :killed}
    server = Jido.Test.AgentServer.Assertions.replacement(root, server)

    replacement =
      eventually(fn ->
        case Jido.Test.AgentServer.Assertions.plugin(server, Timer) do
          %{pid: pid} when pid != timer_plugin.pid -> pid
          _other -> nil
        end
      end)

    assert Map.has_key?(:sys.get_state(replacement).interval_jobs, :review)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(
               server,
               signal("runtime.directive", %{
                 event: :paused,
                 directive: Timer.pause(:review)
               })
             )

    eventually(fn -> :sys.get_state(replacement).interval_jobs == %{} end)
    assert Server.snapshot(server).agent.state.timer.every.review.status == :paused

    paused_monitor = Process.monitor(replacement)
    Process.exit(replacement, :kill)
    assert_receive {:DOWN, ^paused_monitor, :process, _pid, :killed}
    server = Jido.Test.AgentServer.Assertions.replacement(root, server)

    paused_replacement =
      eventually(fn ->
        case Jido.Test.AgentServer.Assertions.plugin(server, Timer) do
          %{pid: pid} when pid != replacement -> pid
          _other -> nil
        end
      end)

    assert :sys.get_state(paused_replacement).interval_jobs == %{}
  end

  @tag obligation: "jido.plugin.timer.I7"
  test "Agent restore recreates a future timer with the same generation" do
    path = Path.join(System.tmp_dir!(), unique_id("timer-restore"))
    on_exit(fn -> File.rm_rf!(path) end)
    persistence = {Jido.Persistence.File, path: path}
    instance = :"timer_restore_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: instance, namespace: "test/timer/#{System.unique_integer([:positive])}", persistence: persistence},
      id: {Jido, instance}
    )

    id = unique_id("timed-agent")

    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(instance, TimedAgent,
        id: id,
        persistence_mode: :create
      )

    {:ok, arm} = TimedAgent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Server.call(server, arm)

    initial_runtime = Jido.Test.AgentServer.Assertions.plugin(server, Timer).pid

    {initial_definition, initial_job, _ref, _token} =
      eventually(fn ->
        Map.get(:sys.get_state(initial_runtime).cron_jobs, "job-1")
      end)

    assert Process.alive?(initial_job)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(server)

    {:ok, restored} =
      Jido.Test.AgentServer.Assertions.start_agent(instance, TimedAgent,
        id: id,
        persistence_mode: :restore
      )

    runtime = Jido.Test.AgentServer.Assertions.plugin(restored, Timer).pid
    {definition, job, _ref, _token} = :sys.get_state(runtime).cron_jobs["job-1"]
    assert Process.alive?(job)
    assert definition.generation == initial_definition.generation
  end

  @tag obligation: "jido.plugin.timer.I7"
  test "Agent restore recreates an active interval with the same generation" do
    path = Path.join(System.tmp_dir!(), unique_id("timer-interval-restore"))
    on_exit(fn -> File.rm_rf!(path) end)
    persistence = {Jido.Persistence.File, path: path}
    instance = :"timer_interval_restore_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: instance, namespace: "test/timer/#{System.unique_integer([:positive])}", persistence: persistence},
      id: {Jido, instance}
    )

    id = unique_id("interval-agent")

    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(instance, TimedAgent,
        id: id,
        persistence_mode: :create
      )

    {:ok, arm} = TimedAgent.arm_interval_signal(%{job_id: "job-1", interval_ms: 200})
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Server.call(server, arm)

    interval_runtime = Jido.Test.AgentServer.Assertions.plugin(server, Timer).pid

    assert {initial_definition, timer, _token, _scheduled_at} =
             eventually(fn ->
               Map.get(:sys.get_state(interval_runtime).interval_jobs, "job-1")
             end)

    assert initial_definition.generation == 1
    assert is_integer(Process.read_timer(timer))

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(server)

    {:ok, restored} =
      Jido.Test.AgentServer.Assertions.start_agent(instance, TimedAgent,
        id: id,
        persistence_mode: :restore
      )

    runtime = Jido.Test.AgentServer.Assertions.plugin(restored, Timer).pid
    {definition, timer, _token, _scheduled_at} = :sys.get_state(runtime).interval_jobs["job-1"]
    assert is_integer(Process.read_timer(timer))
    assert definition.generation == initial_definition.generation
  end

  @tag obligation: "jido.plugin.timer.I8"
  test "invalid runtime clocks fail activation and own one retry timer" do
    for {time_scale, reason} <- [
          {ZeroTimeScale, {:invalid_time_scale_speedup, 0}},
          {InvalidNowTimeScale, {:invalid_time_scale_now, :not_a_datetime}},
          {RaisingTimeScale,
           {:time_scale_unavailable, :speedup, {:error, %RuntimeError{message: "clock unavailable"}}}},
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

  @tag obligation: "jido.plugin.timer.I8"
  test "failed cron activation retries, ignores stale work, and recovers" do
    runtime = %{runtime(test: self()) | partition: self()}
    tracked = spec("0 0 1 1 *", 1)

    assert {:reply, {:error, {:cron_activation_failed, :job, :nonportable_occurrence_scope}}, failed} =
             reconcile(runtime, %{job: tracked}, 1)

    assert failed.cron_jobs == %{}
    assert {:noreply, ^failed} = Runtime.handle_info({:retry_reconcile, make_ref(), 1}, failed)

    Process.cancel_timer(failed.retry_timer)

    assert {:noreply, retrying} =
             Runtime.handle_info({:retry_reconcile, failed.retry_token, 1}, failed)

    assert_receive {:timer_retry_failed, 1, {:cron_activation_failed, :job, :nonportable_occurrence_scope}}

    Process.cancel_timer(retrying.retry_timer)

    assert {:noreply, recovered} =
             Runtime.handle_info(
               {:retry_reconcile, retrying.retry_token, 1},
               %{retrying | partition: nil}
             )

    try do
      assert_receive {:timer_retry_succeeded, 1}
      assert recovered.retry_timer == nil
      assert recovered.retry_token == nil
      assert {^tracked, job, _ref, _token} = recovered.cron_jobs.job
      assert Process.alive?(job)
    after
      Runtime.terminate(:normal, recovered)
    end
  end

  @tag obligation: ["jido.plugin.timer.I8", "jido.plugin.timer.I9"]
  test "startup preserves state failures and server calls contain runtime loss" do
    {agent_server, monitor} =
      spawn_monitor(fn ->
        receive do
          {:"$gen_call", from, {:plugin_state, Timer}} ->
            :gen_statem.reply(from, {:error, :state_unavailable})
        end
      end)

    state = %{runtime() | agent_server: agent_server}

    assert {:stop, {:timer_boot_failed, :state_unavailable}, ^state} =
             Runtime.handle_continue(:reconcile_agent, state)

    assert_receive {:DOWN, ^monitor, :process, ^agent_server, :normal}

    assert {:stop, {:timer_boot_failed, {:agent_server_unavailable, _reason}}, ^state} =
             Runtime.handle_continue(:reconcile_agent, state)

    dead = spawn(fn -> :ok end)
    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _reason}

    assert {:error, {:timer_runtime_unavailable, _reason}} =
             Timer.await_ready(dead, timeout: 10)

    assert {:error, {:timer_runtime_unavailable, _reason}} =
             Timer.dispatch(
               dead,
               Timer.cancel(:job),
               context(runtime(), %{cron: %{}}, 1),
               timeout: 10
             )
  end

  @tag obligation: "jido.plugin.timer.I9"
  test "the Plugin declares one runtime child and reports readiness after reconciliation" do
    test_pid = self()
    agent_server = spawn(fn -> timer_agent(test_pid, %{}) end)

    init = %Init{
      agent_server: agent_server,
      agent_id: "ready-agent",
      module: Timer,
      options: [test: self()]
    }

    spec = Timer.child_spec(init)
    assert spec.id == Timer
    assert spec.start == {Runtime, :start_link, [init]}
    assert runtime().desired_cron == %{}
    timer = start_supervised!(spec)
    assert_receive {:timer_plugin_ready, ^timer}
    assert :ok = Timer.await_ready(timer, timeout: 100)
  end

  @tag obligation: ["jido.plugin.timer.I7", "jido.plugin.timer.I8"]
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
    assert_receive {:timer_retry_scheduled, :job, :killed, :nonportable_occurrence_scope}
    SchedEx.cancel(job)
    Runtime.terminate(:normal, retrying)
  end
end
