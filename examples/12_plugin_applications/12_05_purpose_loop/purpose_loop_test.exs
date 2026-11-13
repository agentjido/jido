Code.require_file("clock.ex", __DIR__)
Code.require_file("purpose_loop.ex", __DIR__)

defmodule Jido.Examples.Applications.PurposeLoopTest do
  use Jido.Test.Case, async: false
  @moduletag :integration
  alias Jido.Persistence
  alias Jido.Plugin.Scheduler
  alias Jido.Examples.Applications.PurposeLoop.{Agent, Signals}

  test "scheduled finite turns continue without client input and ignore duplicate ticks", %{
    jido: jido
  } do
    {:ok, agent_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("purpose-loop"))

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 agent_server,
                 signal("examples.applications.purpose_loop.start", %{
                   purpose: "review queued units",
                   work: ["a", "b", "c"],
                   work_delay_ms: 30,
                   idle_delay_ms: 150
                 })
               )

      assert turn_result.status in [:committed, :waiting]
      started = Jido.AgentServer.snapshot(agent_server).agent
    )

    assert started.state.phase == :running
    assert started.state.completed == []

    duplicate = Signals.tick(started.state.generation, started.state.next_sequence)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent_server, duplicate)

      assert turn_result.status in [:committed, :waiting]
      first_turn = Jido.AgentServer.snapshot(agent_server).agent
    )

    assert first_turn.state.completed == ["a"]

    eventually(
      fn ->
        state = Jido.AgentServer.snapshot(agent_server).agent.state

        state.phase == :idle and state.completed == ["a", "b", "c"] and
          state.last_completed == "c" and state.budget_remaining == 0
      end,
      timeout: 2_000
    )

    eventually(fn -> Jido.AgentServer.snapshot(agent_server).agent.state.ignored_ticks > 0 end,
      timeout: 1_000
    )

    idle_state = Jido.AgentServer.snapshot(agent_server).agent.state

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 agent_server,
                 signal("examples.applications.purpose_loop.enqueue", %{work: ["d"]})
               )

      assert turn_result.status in [:committed, :waiting]
      woken = Jido.AgentServer.snapshot(agent_server).agent
    )

    assert woken.state.phase == :running
    assert woken.state.generation == idle_state.generation + 1

    eventually(
      fn ->
        state = Jido.AgentServer.snapshot(agent_server).agent.state

        state.phase == :idle and state.completed == ["a", "b", "c", "d"] and
          state.last_completed == "d" and state.budget == 4 and
          state.budget_remaining == 0
      end,
      timeout: 2_000
    )

    eventually(fn -> Jido.AgentServer.snapshot(agent_server).agent.state.idle_ticks > 0 end,
      timeout: 2_000
    )

    assert :ok = Jido.stop_agent(jido, agent_server)
    eventually(fn -> Jido.resident_agent_count(jido) == 0 end)
  end

  test "a paused loop restores, resumes, drains, rejects new work, and cleans up", c do
    id = unique_id("purpose-loop-recovery")
    table = String.to_atom("purpose_loop_#{System.unique_integer([:positive])}")
    persistence = {Jido.Persistence.ETS, table: table}
    %{jido: jido} = restart_jido!(c, persistence)

    {:ok, agent_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent,
        id: id,
        persistence_mode: :create
      )

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 agent_server,
                 signal("examples.applications.purpose_loop.start", %{
                   purpose: "finish after restart",
                   work: ["one", "two", "three", "four"],
                   work_delay_ms: 80,
                   idle_delay_ms: 250
                 })
               )

      assert turn_result.status in [:committed, :waiting]
      started = Jido.AgentServer.snapshot(agent_server).agent
    )

    first_tick = Signals.tick(started.state.generation, started.state.next_sequence)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent_server, first_tick)

      assert turn_result.status in [:committed, :waiting]
      first_turn = Jido.AgentServer.snapshot(agent_server).agent
    )

    assert first_turn.state.completed == ["one"]

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 agent_server,
                 signal("examples.applications.purpose_loop.pause")
               )

      assert turn_result.status in [:committed, :waiting]
      paused = Jido.AgentServer.snapshot(agent_server).agent
    )

    assert paused.state.phase == :paused
    assert paused.state.last_completed == "one"
    assert paused.state.budget_remaining == 3

    eventually(fn -> Jido.AgentServer.snapshot(agent_server).agent.state.ignored_ticks > 0 end,
      timeout: 1_000
    )

    assert Jido.AgentServer.snapshot(agent_server).agent.state.completed == ["one"]
    old_scheduler = scheduler_runtime(agent_server)
    old_agent_ref = Process.monitor(agent_server)
    old_scheduler_ref = Process.monitor(old_scheduler)

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(agent_server)
    assert_receive {:DOWN, ^old_agent_ref, :process, ^agent_server, _reason}, 1_000
    assert_receive {:DOWN, ^old_scheduler_ref, :process, ^old_scheduler, _reason}, 1_000

    assert {:ok, restored} =
             Persistence.load_agent(persistence, Agent, id, instance: jido)

    assert restored.state.phase == :paused
    assert restored.state.completed == ["one"]
    assert restored.state.last_completed == "one"
    assert restored.state.budget_remaining == 3
    assert restored.state.remaining == ["two", "three", "four"]

    assert {:ok, restarted_server} = Jido.thaw(jido, Agent, id)

    assert :ok = Jido.AgentServer.await_ready(restarted_server)
    assert restarted_server != agent_server

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 restarted_server,
                 signal("examples.applications.purpose_loop.resume")
               )

      assert turn_result.status in [:committed, :waiting]
      resumed = Jido.AgentServer.snapshot(restarted_server).agent
    )

    assert resumed.state.phase == :running

    eventually(
      fn -> length(Jido.AgentServer.snapshot(restarted_server).agent.state.completed) >= 2 end,
      timeout: 2_000
    )

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 restarted_server,
                 signal("examples.applications.purpose_loop.drain")
               )

      assert turn_result.status in [:committed, :waiting]
      draining = Jido.AgentServer.snapshot(restarted_server).agent
    )

    assert draining.state.phase == :draining

    eventually(
      fn ->
        state = Jido.AgentServer.snapshot(restarted_server).agent.state

        state.phase == :drained and
          state.completed == ["one", "two", "three", "four"]
      end,
      timeout: 2_000
    )

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(
                 restarted_server,
                 signal("examples.applications.purpose_loop.enqueue", %{work: ["late"]})
               )

      assert turn_result.status in [:committed, :waiting]
      rejected = Jido.AgentServer.snapshot(restarted_server).agent
    )

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
    assert Jido.resident_agent_count(jido) == 0
    assert :ok = Persistence.delete_agent(persistence, Agent, id, instance: jido)
  end

  defp scheduler_runtime(agent_server) do
    eventually(fn ->
      case Jido.Test.AgentServer.ExampleRuntime.plugin(
             Jido.Test.AgentServer.ExampleRuntime.activation(agent_server),
             Scheduler
           ) do
        pid when is_pid(pid) -> pid
        _child -> nil
      end
    end)
  end
end
