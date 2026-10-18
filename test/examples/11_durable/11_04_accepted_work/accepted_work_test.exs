defmodule JidoTest.Examples.Durable.AcceptedWorkTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.AcceptedWork, as: Example

  test "a topology member commits its Flow and restores completion without another Turn", c do
    id = unique_id("accepted-report")
    persistence = {Jido.Persistence.File, path: c.tmp_dir}

    assert {:ok, root} =
             Jido.start_agent(c.jido, Example.Team,
               id: id,
               persistence: persistence
             )

    assert :ok = Server.await_ready(root)
    assert [server] = Server.members(root, :reports)
    assert {:ok, request} = Example.request_signal(%{topic: "  OTP  "})
    assert {:ok, agent, []} = Server.call(server, request)
    assert agent.state == %{report: "Report: OTP"}
    receipt = Server.status(server).durable_turn
    assert receipt.status == :completed
    member_id = agent.id
    activation = Server.activation(root)
    monitor = Process.monitor(activation)
    Process.exit(activation, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^activation, :killed}, 5_000

    awake =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != root -> pid
          _ -> nil
        end
      end)

    assert :ok = Server.await_ready(awake)
    assert [restored] = Server.members(awake, :reports)
    assert Server.agent(restored) == agent
    assert Server.agent(restored).id == member_id
    assert Server.status(restored).durable_turn == receipt
    assert {:error, _} = Server.call(restored, %{request | data: %{topic: 42}})
    assert Server.agent(restored) == agent
    assert :ok = Jido.stop_agent(c.jido, awake)
    assert Jido.agent_count(c.jido) == 0
  end
end
