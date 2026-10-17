Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.LoggingTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  import ExUnit.CaptureLog
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server2.I25"
  test "Action and Flow errors reach callers but raw input and errors do not enter runtime logs",
       c do
    server = F.start(c)

    logs =
      capture_log([level: :debug, metadata: [:agent_id, :turn_id]], fn ->
        for type <- ["work", "flow"] do
          signal = F.signal(%{mode: :fail, private_input: "SERVER2_PRIVATE_INPUT"}, type)
          assert {:error, error} = Server.call(server, signal)
          assert inspect(error) =~ "SERVER2_PRIVATE_ERROR"
          assert :ok = Server.cast(server, signal)
          assert {:error, _} = F.barrier(server)
        end
      end)

    assert logs =~ "AgentServer cast turn failed"
    assert logs =~ c.agent.id
    refute logs =~ "SERVER2_PRIVATE_ERROR"
    refute logs =~ "SERVER2_PRIVATE_INPUT"
    refute logs =~ "Runnable failed for node"
    F.unchanged(server, c.agent)
    F.clean(c.runner)
  end
end
