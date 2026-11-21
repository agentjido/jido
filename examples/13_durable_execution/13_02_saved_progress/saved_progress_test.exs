Code.require_file("../support/saved_progress_advance.ex", __DIR__)
Code.require_file("../support/saved_progress_agent.ex", __DIR__)
Code.require_file("../support/durable_step_probe.exs", __DIR__)

defmodule Jido.Examples.Durable.SavedProgressTest do
  use Jido.Test.Case, async: false
  @moduletag :integration
  alias Jido.Examples.Durable.SavedProgress
  alias Jido.Test.Examples.Durable.{ObservedAgent, StepProbe}

  test "the ten-step Flow adds ten" do
    assert {:ok, %{value: 10}} = Jido.Exec.run(SavedProgress, %{value: 0})
  end

  test "AgentServer saves steps 1–5 and resumes the current Turn at step 6", c do
    start_supervised!({StepProbe, self()})
    id = unique_id("saved-progress")
    persistence = Jido.Persistence.ETS
    c = restart_jido!(c, persistence)

    assert {:ok, server} = Jido.start_agent(c.jido, ObservedAgent.new(id))

    assert :ok = Jido.AgentServer.await_ready(server)
    {:ok, request} = SavedProgress.Agent.run_signal(%{value: 0})
    pending = Jido.AgentServer.submit(server, request)
    assert_receive {:step_6_running, action, 5}, 5_000
    turn = Jido.AgentServer.status(server).active_turn_id
    assert StepProbe.records().completed == Enum.to_list(1..5)
    monitor = Process.monitor(action)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^action, _}, 5_000

    restored =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != server -> pid
          _ -> nil
        end
      end)

    assert :ok = Jido.AgentServer.await_ready(restored)
    assert_receive {:step_6_running, _, 5}, 5_000
    assert Jido.AgentServer.status(restored).active_turn_id == turn
    assert Jido.AgentServer.snapshot(restored).agent.state == %{value: 0}
    assert StepProbe.records().completed == Enum.to_list(1..5)
    assert :ok = StepProbe.release()
    eventually(fn -> Jido.AgentServer.snapshot(restored).agent.state == %{value: 10} end)

    assert StepProbe.records().started ==
             Enum.map(1..6, &{&1, &1 - 1}) ++ Enum.map(6..10, &{&1, &1 - 1})

    assert StepProbe.records().completed == Enum.to_list(1..10)

    assert %Jido.AgentServer.Status{work_state: :idle, active_turn_id: nil} =
             Jido.AgentServer.status(restored)

    assert {:error, _} = Jido.AgentServer.await(pending)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(restored)
    assert Jido.resident_agent_count(c.jido) == 0
  end
end
