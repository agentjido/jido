defmodule JidoTest.Agent.ScheduledOccurrenceTest do
  use JidoTest.Case, async: false
  @moduletag capability: "REC-03"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ScheduledOccurrenceProbe, as: Agent
  alias Jido.Plugin.Scheduler
  alias JidoTest.ScheduledOccurrenceFixtures.{Clock, TimedAgent}

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

    assert {:ok, candidate, [_cron]} =
             Agent.cmd(agent, Agent.arm_schedule_signal!("job-1", "* * * * * *"))

    assert agent.state.scheduler.cron == %{}
    assert candidate.state.generation == 1
    assert candidate.state.scheduler.cron["job-1"].generation == 1

    assert candidate.state.scheduler.cron["job-1"].message.data == %{
             job_id: "job-1",
             generation: 1
           }
  end

  test "runtime ticks carry a logical occurrence ID independent of Signal delivery", %{jido: jido} do
    assert {:ok, server} = Jido.start_agent(jido, Agent, id: unique_id())
    assert {:ok, _} = Agent.arm_schedule(server, "job-1", "* * * * * *")

    ticks =
      eventually(
        fn ->
          case Server.agent(server).state.ticks do
            [first, second | _] -> [first, second]
            _ -> nil
          end
        end,
        timeout: 3_000
      )

    [first, second] = ticks
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

  test "an early timer cannot deliver a future slot before the real clock reaches it", %{
    jido: jido
  } do
    assert {:ok, server} = Jido.start_agent(jido, Agent, id: unique_id())
    assert {:ok, _} = Agent.arm_schedule(server, "job-1", "* * * * * *")
    scheduler = Server.children(server)[{:plugin, Scheduler}].pid
    {_spec, runner, _ref} = eventually(fn -> :sys.get_state(scheduler).cron_jobs["job-1"] end)
    # Force the same early wake-up that millisecond truncation can cause.
    # A future whole-second slot gives a controlled barrier without a sleep.
    slot = DateTime.utc_now() |> DateTime.add(2, :second) |> DateTime.truncate(:second)

    :sys.replace_state(runner, fn state ->
      Process.cancel_timer(state.timer_ref)
      %{state | scheduled_at: slot}
    end)

    send(runner, :run)
    :sys.get_state(runner)
    assert DateTime.compare(DateTime.utc_now(), slot) != :lt

    tick =
      eventually(fn ->
        Enum.find(
          Server.agent(server).state.ticks,
          fn tick ->
            {:ok, time, _} = DateTime.from_iso8601(tick.occurrence.scheduled_at)
            DateTime.compare(time, slot) == :eq
          end
        )
      end)

    assert tick.occurrence.id != ""
  end

  test "repeated clock slots keep identity while generation replacement changes it", c do
    server = start_agent(c)
    assert {:ok, _} = Agent.arm_schedule(server, "job-1", "* * * * * *")
    [first, second | _] = await_ticks(server, 2)
    assert first.signal_id != second.signal_id
    assert first.occurrence == second.occurrence
    assert first.occurrence.scheduled_at == "2030-01-01T00:00:01.000000Z"

    assert {:ok, _} = Agent.arm_schedule(server, "job-1", "* * * * * *")

    replacement =
      eventually(fn ->
        Enum.find(Server.agent(server).state.ticks, &(&1.occurrence.generation == 2))
      end)

    assert replacement.occurrence.scheduled_at == first.occurrence.scheduled_at
    assert replacement.occurrence.id != first.occurrence.id
  end

  test "Scheduler restart retains the occurrence coordinates", c do
    server = start_agent(c)
    assert {:ok, _} = Agent.arm_schedule(server, "job-1", "* * * * * *")
    [first | _] = await_ticks(server, 1)
    scheduler = Server.children(server)[{:plugin, Scheduler}].pid
    kill(scheduler)

    eventually(fn -> Server.children(server)[{:plugin, Scheduler}].pid != scheduler end)
    count = length(Server.agent(server).state.ticks)
    ticks = await_ticks(server, count + 1)
    assert List.last(ticks).occurrence == first.occurrence
    assert List.last(ticks).signal_id != first.signal_id
  end

  test "Agent restore retains identity and the next scheduled instant changes it", c do
    server = start_agent(c)
    assert {:ok, _} = Agent.arm_schedule(server, "job-1", "* * * * * *")
    [first | _] = await_ticks(server, 1)
    kill(server)

    restored = start_agent(c, :required)
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

  defp start_agent(c, restore \\ false) do
    assert {:ok, server} =
             Jido.start_agent(c.jido, TimedAgent,
               id: c.agent_id,
               persistence: c.persistence,
               restore: restore,
               restart: :temporary
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
