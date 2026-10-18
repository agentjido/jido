defmodule JidoTest.Examples.Durable.SavedProgressTest do
  use JidoTest.Case, async: false
  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.SavedProgress
  alias JidoTest.Examples.Durable.{ObservedAgent, StepProbe}

  test "the ten-step Flow adds ten" do
    assert {:ok, %{value: 10}} = Jido.Exec.run(SavedProgress, %{value: 0})
  end

  test "AgentServer saves steps 1–5 and resumes the current Turn at step 6", c do
    start_supervised!({StepProbe, self()})
    id = unique_id("saved-progress")
    persistence = Jido.Persistence.ETS

    assert {:ok, server} =
             Jido.start_agent(c.jido, ObservedAgent.new(id), persistence: persistence)

    assert :ok = Server.await_ready(server)
    {:ok, request} = SavedProgress.Agent.run_signal(%{value: 0})
    pending = Server.submit(server, request)
    assert_receive {:step_6_running, action, 5}, 5_000
    turn = Server.status(server).active.turn_id
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

    assert :ok = Server.await_ready(restored)
    assert_receive {:step_6_running, _, 5}, 5_000
    assert Server.status(restored).active.turn_id == turn
    assert Server.agent(restored).state == %{value: 0}
    assert StepProbe.records().completed == Enum.to_list(1..5)
    assert :ok = StepProbe.release()
    eventually(fn -> Server.agent(restored).state == %{value: 10} end)

    assert StepProbe.records().started ==
             Enum.map(1..6, &{&1, &1 - 1}) ++ Enum.map(6..10, &{&1, &1 - 1})

    assert StepProbe.records().completed == Enum.to_list(1..10)
    assert Server.status(restored).durable_turn == %{id: turn, status: :completed}
    assert {:error, _} = Server.await(pending)
    assert :ok = Server.stop(restored)
    assert Jido.agent_count(c.jido) == 0
  end
end
