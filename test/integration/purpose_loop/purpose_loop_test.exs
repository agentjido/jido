Code.require_file("example_test.exs", __DIR__)

defmodule JidoTest.Integration.PurposeLoopTest do
  use JidoTest.Case, async: false

  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias Jido.Plugin.Scheduler
  alias JidoTest.Integration.PurposeLoop.{Agent, Signals}

  test "scheduled finite turns continue without client input and ignore duplicate ticks", %{
    jido: jido
  } do
    {:ok, agent_server} = Jido.start_agent(jido, Agent, id: unique_id("purpose-loop"))

    assert {:ok, started} =
             Server.call(
               agent_server,
               signal("purpose.start", %{
                 purpose: "review queued units",
                 work: ["a", "b", "c"],
                 work_delay_ms: 30,
                 idle_delay_ms: 150
               })
             )

    assert started.state.phase == :running
    assert started.state.completed == []

    duplicate = Signals.tick(started.state.generation, started.state.next_sequence)
    assert {:ok, first_turn} = Server.call(agent_server, duplicate)
    assert first_turn.state.completed == ["a"]

    eventually(
      fn ->
        state = Server.agent(agent_server).state

        state.phase == :idle and state.completed == ["a", "b", "c"] and
          state.last_completed == "c" and state.budget_remaining == 0
      end,
      timeout: 2_000
    )

    eventually(fn -> Server.agent(agent_server).state.ignored_ticks > 0 end,
      timeout: 1_000
    )

    idle_state = Server.agent(agent_server).state

    assert {:ok, woken} =
             Server.call(agent_server, signal("purpose.enqueue", %{work: ["d"]}))

    assert woken.state.phase == :running
    assert woken.state.generation == idle_state.generation + 1

    eventually(
      fn ->
        state = Server.agent(agent_server).state

        state.phase == :idle and state.completed == ["a", "b", "c", "d"] and
          state.last_completed == "d" and state.budget == 4 and
          state.budget_remaining == 0
      end,
      timeout: 2_000
    )

    eventually(fn -> Server.agent(agent_server).state.idle_ticks > 0 end,
      timeout: 2_000
    )

    assert :ok = Jido.stop_agent(jido, agent_server)
    eventually(fn -> Jido.agent_count(jido) == 0 end)
  end

  test "a paused loop restores, resumes, drains, rejects new work, and cleans up", %{
    jido: jido
  } do
    id = unique_id("purpose-loop-recovery")
    table = String.to_atom("purpose_loop_#{System.unique_integer([:positive])}")
    persistence = {Jido.Persistence.ETS, table: table}

    {:ok, agent_server} =
      Jido.start_agent(jido, Agent,
        id: id,
        persistence: persistence,
        restore: false
      )

    assert {:ok, started} =
             Server.call(
               agent_server,
               signal("purpose.start", %{
                 purpose: "finish after restart",
                 work: ["one", "two", "three", "four"],
                 work_delay_ms: 80,
                 idle_delay_ms: 250
               })
             )

    first_tick = Signals.tick(started.state.generation, started.state.next_sequence)
    assert {:ok, first_turn} = Server.call(agent_server, first_tick)
    assert first_turn.state.completed == ["one"]

    assert {:ok, paused} = Server.call(agent_server, signal("purpose.pause"))
    assert paused.state.phase == :paused
    assert paused.state.last_completed == "one"
    assert paused.state.budget_remaining == 3

    eventually(fn -> Server.agent(agent_server).state.ignored_ticks > 0 end,
      timeout: 1_000
    )

    assert Server.agent(agent_server).state.completed == ["one"]
    old_scheduler = scheduler_runtime(agent_server)
    old_agent_ref = Process.monitor(agent_server)
    old_scheduler_ref = Process.monitor(old_scheduler)

    assert :ok = Server.hibernate(agent_server)
    assert_receive {:DOWN, ^old_agent_ref, :process, ^agent_server, _reason}, 1_000
    assert_receive {:DOWN, ^old_scheduler_ref, :process, ^old_scheduler, _reason}, 1_000

    assert {:ok, restored} =
             Persistence.load_agent(persistence, Agent, id, instance: jido)

    assert restored.state.phase == :paused
    assert restored.state.completed == ["one"]
    assert restored.state.last_completed == "one"
    assert restored.state.budget_remaining == 3
    assert restored.state.remaining == ["two", "three", "four"]

    assert {:ok, restarted_server} =
             Jido.thaw(jido, Agent, id, persistence: persistence)

    assert restarted_server != agent_server

    assert {:ok, resumed} = Server.call(restarted_server, signal("purpose.resume"))
    assert resumed.state.phase == :running

    eventually(fn -> length(Server.agent(restarted_server).state.completed) >= 2 end,
      timeout: 2_000
    )

    assert {:ok, draining} = Server.call(restarted_server, signal("purpose.drain"))
    assert draining.state.phase == :draining

    eventually(
      fn ->
        state = Server.agent(restarted_server).state

        state.phase == :drained and
          state.completed == ["one", "two", "three", "four"]
      end,
      timeout: 2_000
    )

    assert {:ok, rejected} =
             Server.call(restarted_server, signal("purpose.enqueue", %{work: ["late"]}))

    assert rejected.state.phase == :drained
    assert rejected.state.rejected_work == 1
    assert rejected.state.completed == ["one", "two", "three", "four"]

    scheduler = scheduler_runtime(restarted_server)
    agent_ref = Process.monitor(restarted_server)
    scheduler_ref = Process.monitor(scheduler)

    assert :ok = Jido.stop_agent(jido, restarted_server)
    assert_receive {:DOWN, ^agent_ref, :process, ^restarted_server, _reason}, 1_000
    assert_receive {:DOWN, ^scheduler_ref, :process, ^scheduler, _reason}, 1_000

    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
    assert Jido.agent_count(jido) == 0
    assert :ok = Persistence.delete_agent(persistence, Agent, id, instance: jido)
  end

  defp scheduler_runtime(agent_server) do
    eventually(fn ->
      case Server.children(agent_server)[{:plugin, Scheduler}] do
        %{pid: pid} when is_pid(pid) -> pid
        _child -> nil
      end
    end)
  end
end
