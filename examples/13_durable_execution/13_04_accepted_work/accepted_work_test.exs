Code.require_file("accepted_work.ex", __DIR__)

defmodule Jido.Examples.Durable.AcceptedWorkTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.AcceptedWork, as: Example
  alias Jido.Test.AgentServer.TopologyAssertions

  test "a topology member commits its Flow and restores completion without another Turn", c do
    id = unique_id("accepted-report")
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    c = restart_jido!(c, persistence)

    assert {:ok, root} =
             Jido.start_agent(c.jido, Example.Team, id: id)

    assert :ok = Jido.AgentServer.await_ready(root)
    assert [server] = TopologyAssertions.members(root)
    assert {:ok, request} = Example.request_signal(%{topic: "  OTP  "})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed} = receipt} =
             Server.call(server, request)

    agent = Server.snapshot(server).agent
    assert agent.state == %{report: "Report: OTP"}
    member_id = agent.id
    activation = Jido.Test.AgentServer.ExampleRuntime.activation(root)
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

    assert :ok = Jido.AgentServer.await_ready(awake)
    assert [restored] = TopologyAssertions.members(awake)
    assert Jido.AgentServer.snapshot(restored).agent == agent
    assert Jido.AgentServer.snapshot(restored).agent.id == member_id
    assert receipt.agent_address.id == member_id

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             Server.call(restored, %{request | data: %{topic: 42}})

    assert Jido.AgentServer.snapshot(restored).agent == agent
    assert :ok = Jido.stop_agent(c.jido, awake)
    assert Jido.resident_agent_count(c.jido) == 0
  end
end
