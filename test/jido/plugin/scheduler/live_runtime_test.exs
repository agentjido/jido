defmodule Jido.Plugin.Scheduler.LiveRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Scheduler
  alias Jido.Signal
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent
  alias JidoTest.ScheduledOccurrenceFixtures.{Clock, FastRuntimeAgent}

  setup do
    start_supervised!({Clock, []})
    :ok
  end

  defp eventually_agent(server, predicate, timeout \\ 3_000) do
    eventually(
      fn ->
        agent = Server.agent(server)
        if predicate.(agent), do: agent
      end,
      timeout: timeout
    )
  end

  test "delayed and cron Signals return through the Agent mailbox", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, FastRuntimeAgent, id: unique_id("schedule"))

    delayed = Signal.new!("runtime.record", %{event: :delayed}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :scheduled,
                 directive: Scheduler.schedule(10, delayed)
               })
             )

    assert agent.state.events == [:scheduled]
    eventually_agent(pid, &(&1.state.events == [:scheduled, :delayed]))

    tick = Signal.new!("cron.tick", %{}, source: "/test")

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :cron_registered,
                 directive: Scheduler.cron(:heartbeat, "* * * * * * *", tick)
               })
             )

    assert Map.has_key?(Server.agent(pid).state.scheduler.cron, :heartbeat)
    eventually_agent(pid, &(&1.state.ticks > 0), 5_000)

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :cron_cancelled,
                 directive: Scheduler.cancel(:heartbeat)
               })
             )

    eventually(fn -> Server.agent(pid).state.scheduler.cron == %{} end)
  end

  test "rejects invalid Scheduler data before commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("invalid-scheduler"))
    tick = Signal.new!("cron.tick", %{}, source: "/test")

    for directive <- [
          Scheduler.schedule(10, :not_a_signal),
          Scheduler.cron(:raw_message, "* * * * * * *", :not_a_signal),
          Scheduler.cron(:bad_cron, "not a cron", tick),
          Scheduler.cron(make_ref(), "* * * * * * *", tick),
          Scheduler.cron(:bad_timezone, "* * * * * * *", tick, timezone: "Not/AZone"),
          Scheduler.cron(:bad_generation, "* * * * * * *", tick, generation: -1),
          Scheduler.cron(:bad_generation_type, "* * * * * * *", tick, generation: "1"),
          Scheduler.cron(:large_generation, "* * * * * * *", tick, generation: 2_147_483_648)
        ] do
      assert {:error, _reason} =
               Server.call(
                 pid,
                 signal("runtime.directive", %{event: :must_not_commit, directive: directive})
               )
    end

    assert Server.agent(pid).state.events == []
    assert Server.agent(pid).state.scheduler.cron == %{}
    assert Server.status(pid).state_version == 0

    agent = Server.agent(pid)

    invalid_state =
      put_in(agent.state.scheduler.cron[:restored], %{
        cron_expression: "not a cron",
        message: tick,
        timezone: "Etc/UTC"
      })

    assert {:error, %Jido.Error.ValidationError{}} = Jido.Agent.transition(agent, invalid_state)
  end

  test "reduces Scheduler changes in list order and reconciles the final state", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("scheduler-order"))
    tick = Signal.new!("cron.tick", %{}, source: "/test")
    cron = Scheduler.cron(:heartbeat, "* * * * * * *", tick)
    cancel = Scheduler.cancel(:heartbeat)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :enabled,
                 directives: [cancel, cron]
               })
             )

    assert Map.has_key?(agent.state.scheduler.cron, :heartbeat)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :disabled,
                 directives: [cron, cancel]
               })
             )

    assert agent.state.scheduler.cron == %{}
  end

  test "restarts the Scheduler runtime from committed Plugin state", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, FastRuntimeAgent, id: unique_id("scheduler-restart"))

    tick = Signal.new!("cron.tick", %{}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :scheduled,
                 directive: Scheduler.cron(:heartbeat, "* * * * * * *", tick)
               })
             )

    assert Map.has_key?(agent.state.scheduler.cron, :heartbeat)
    child = Server.children(pid)[{:plugin, Scheduler}]
    monitor = Process.monitor(child.pid)
    Process.exit(child.pid, :kill)

    assert_receive {:DOWN, ^monitor, :process, _pid, :killed}

    restarted =
      eventually(fn ->
        case Server.children(pid)[{:plugin, Scheduler}] do
          %{pid: new_pid} = current when is_pid(new_pid) and new_pid != child.pid -> current
          _child -> nil
        end
      end)

    assert Process.alive?(restarted.pid)
    assert Map.has_key?(Server.agent(pid).state.scheduler.cron, :heartbeat)
    eventually_agent(pid, &(&1.state.ticks > 0), 5_000)
  end

  test "the Scheduler runtime restarts a failed cron Job", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("cron-job-restart"))
    tick = Signal.new!("cron.tick", %{}, source: "/test")

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :scheduled,
                 directive: Scheduler.cron(:heartbeat, "* * * * * * *", tick)
               })
             )

    scheduler = eventually(fn -> Server.children(pid)[{:plugin, Scheduler}] end)

    {_spec, old_job_pid, _ref} =
      eventually(fn ->
        :sys.get_state(scheduler.pid).cron_jobs[:heartbeat]
      end)

    monitor = Process.monitor(old_job_pid)
    Process.exit(old_job_pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^old_job_pid, :killed}, 2_000

    new_job_pid =
      eventually(fn ->
        case :sys.get_state(scheduler.pid).cron_jobs[:heartbeat] do
          {_spec, current_job, _ref}
          when is_pid(current_job) and current_job != old_job_pid ->
            current_job

          _job ->
            nil
        end
      end)

    assert Process.alive?(new_job_pid)

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :cancelled,
                 directive: Scheduler.cancel(:heartbeat)
               })
             )

    eventually(fn -> :sys.get_state(scheduler.pid).cron_jobs == %{} end)
  end
end
