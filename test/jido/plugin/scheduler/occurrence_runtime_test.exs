defmodule Jido.Plugin.Scheduler.OccurrenceRuntimeTest do
  use JidoTest.Case, async: false
  @moduletag capability: "REC-03"

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Scheduler
  alias JidoTest.ScheduledOccurrenceFixtures.{Clock, TimedAgent}
  alias JidoTest.ScheduledOccurrenceFixtures.TimedAgent, as: Agent

  setup %{jido_pid: jido_pid} do
    start_supervised!({Clock, []})
    path = Path.join(System.tmp_dir!(), unique_id("jido-occurrence"))

    on_exit(fn ->
      refute Process.alive?(jido_pid)
      File.rm_rf!(path)
    end)

    {:ok, agent_id: unique_id(), persistence: {Jido.Persistence.File, path: path}}
  end

  test "the candidate stores recurring schedule intent and its generation" do
    agent = Agent.new!()

    {:ok, command_signal_1} = Agent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})

    assert {:ok, candidate, [_cron]} =
             Agent.cmd(
               agent,
               command_signal_1
             )

    assert agent.state.scheduler.cron == %{}
    assert candidate.state.generation == 1
    assert candidate.state.scheduler.cron["job-1"].generation == 1

    assert candidate.state.scheduler.cron["job-1"].message.data == %{
             job_id: "job-1",
             generation: 1
           }
  end

  test "runtime ticks carry a logical occurrence ID independent of Signal delivery", %{jido: jido} do
    c = %{jido: jido, agent_id: unique_id(), persistence: nil}
    server = start_agent(c)

    {:ok, route_signal_1} = Agent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})

    assert {:ok, _, _} =
             Jido.AgentServer.call(server, route_signal_1, [])

    [first | _] = await_ticks(server, 1)
    Clock.set(~U[2030-01-01 00:00:01.100000Z])

    second =
      eventually(fn ->
        Enum.find(Server.agent(server).state.ticks, &(&1.occurrence.id != first.occurrence.id))
      end)

    assert first.signal_id != second.signal_id
    assert first.data.job_id == "job-1"
    assert first.data.generation == 1

    assert is_binary(first.occurrence.id)
    assert first.occurrence.id != second.occurrence.id
    assert first.occurrence.generation == 1
    assert {:ok, first_time, 0} = DateTime.from_iso8601(first.occurrence.scheduled_at)
    assert {:ok, second_time, 0} = DateTime.from_iso8601(second.occurrence.scheduled_at)
    assert DateTime.compare(first_time, second_time) == :lt
  end

  test "repeated clock slots keep identity while generation replacement changes it", c do
    server = start_agent(c)

    {:ok, route_signal_2} = Agent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})

    assert {:ok, _, _} =
             Jido.AgentServer.call(server, route_signal_2, [])

    [first, second | _] = await_ticks(server, 2)
    assert first.signal_id != second.signal_id
    assert first.occurrence == second.occurrence
    assert first.occurrence.scheduled_at == "2030-01-01T00:00:01.000000Z"

    {:ok, route_signal_3} = Agent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})

    assert {:ok, _, _} =
             Jido.AgentServer.call(server, route_signal_3, [])

    replacement =
      eventually(fn ->
        Enum.find(Server.agent(server).state.ticks, &(&1.occurrence.generation == 2))
      end)

    assert replacement.occurrence.scheduled_at == first.occurrence.scheduled_at
    assert replacement.occurrence.id != first.occurrence.id
  end

  test "Scheduler restart retains the occurrence coordinates", c do
    server = start_agent(c)

    {:ok, route_signal_4} = Agent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})

    assert {:ok, _, _} =
             Jido.AgentServer.call(server, route_signal_4, [])

    [first | _] = await_ticks(server, 1)
    scheduler = JidoTest.AgentServerAssertions.plugin(server, Scheduler).pid
    root = Server.activation(server)
    kill(scheduler)
    server = JidoTest.AgentServerAssertions.replacement(root, server)

    eventually(fn ->
      JidoTest.AgentServerAssertions.plugin(server, Scheduler).pid != scheduler
    end)

    runtime = JidoTest.AgentServerAssertions.plugin(server, Scheduler).pid
    {spec, job, _monitor, token} = :sys.get_state(runtime).cron_jobs["job-1"]
    assert Process.alive?(job)
    assert spec.generation == first.occurrence.generation
    count = length(Server.agent(server).state.ticks)
    {:ok, scheduled_at, 0} = DateTime.from_iso8601(first.occurrence.scheduled_at)
    send(runtime, {:cron_tick, "job-1", token, scheduled_at})
    ticks = await_ticks(server, count + 1)
    assert List.last(ticks).occurrence == first.occurrence
    assert List.last(ticks).signal_id != first.signal_id
  end

  test "Agent restore retains identity and the next scheduled instant changes it", c do
    server = start_agent(c)

    {:ok, route_signal_5} = Agent.arm_schedule_signal(%{job_id: "job-1", cron: "* * * * * *"})

    assert {:ok, _, _} =
             Jido.AgentServer.call(server, route_signal_5, [])

    [first | _] = await_ticks(server, 1)
    assert :ok = Server.stop(server)

    restored = start_agent(c, :restore)
    count = length(Server.agent(restored).state.ticks)
    ticks = await_ticks(restored, count + 1)
    assert List.last(ticks).occurrence == first.occurrence
    assert List.last(ticks).signal_id != first.signal_id

    Clock.set(~U[2030-01-01 00:00:01.100000Z])

    next =
      eventually(fn ->
        Enum.find(Server.agent(restored).state.ticks, &(&1.occurrence.id != first.occurrence.id))
      end)

    assert next.occurrence.generation == 1
    assert next.occurrence.scheduled_at == "2030-01-01T00:00:02.000000Z"
  end

  defp start_agent(c, mode \\ :create) do
    assert {:ok, server} =
             JidoTest.AgentServerAssertions.start_agent(c.jido, TimedAgent,
               id: c.agent_id,
               persistence: c.persistence,
               persistence_mode: mode
             )

    server
  end

  defp await_ticks(server, count) do
    eventually(fn ->
      ticks = Server.agent(server).state.ticks
      if length(ticks) >= count, do: ticks
    end)
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end
end
