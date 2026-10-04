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

    {:ok, first_signal} = Agent.add_signal(%{amount: 3})

    assert {:ok, committed} =
             Jido.AgentServer.call(server, first_signal, [])

    assert committed.state == candidate.state
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Runtime.view(runtime) == {3, 1}

    {:ok, second_signal} = Agent.add_signal(%{amount: 2})
    assert {:ok, latest} = Server.call(server, second_signal)
    assert latest.state.count == 5
    eventually(fn -> Runtime.view(runtime) == {5, 2} end)

    old_runtime_ref = Process.monitor(runtime)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^old_runtime_ref, :process, ^runtime, :killed}

    replacement =
      eventually(fn ->
        case Server.children(server)[{:plugin, Package}] do
          %{pid: pid} when is_pid(pid) and pid != runtime -> pid
          _child -> nil
        end
      end)

    assert Runtime.view(replacement) == {5, 2}

    server_ref = Process.monitor(server)
    runtime_ref = Process.monitor(replacement)
    assert :ok = Server.stop(server)
    assert_receive {:DOWN, ^server_ref, :process, ^server, _}
    assert_receive {:DOWN, ^runtime_ref, :process, ^replacement, _}
  end
end
