defmodule JidoTest.Examples.Plugins.CommitProjectionTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.CommitProjection.{Agent, Package, Runtime}

  test "a Plugin projects committed state without Action-owned Directives", %{jido: jido} do
    signal = signal("examples.plugins.commit_projection.add", %{amount: 3})
    assert {:ok, candidate, []} = Jido.Agent.cmd(Agent.new!(), signal)
    {:ok, server} = Jido.start_agent(jido, Agent, id: unique_id())
    assert %{pid: runtime} = Map.fetch!(Server.children(server), {:plugin, Package})
    assert Runtime.view(runtime) == {0, 0}
    assert {:ok, committed} = Agent.add(server, 3)
    assert committed.state == candidate.state
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Runtime.view(runtime) == {3, 1}

    server_ref = Process.monitor(server)
    runtime_ref = Process.monitor(runtime)
    assert :ok = Server.stop(server)
    assert_receive {:DOWN, ^server_ref, :process, ^server, _}
    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, _}
  end
end
