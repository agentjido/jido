defmodule JidoTest.Examples.Topology.ConnectionChangesTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.AgentTopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.ConnectionChanges, as: Example

  test "connection edits keep processes and the same Turn emits on the accepted edge", %{
    jido: jido
  } do
    server = start_topology(jido, Example)
    [left] = labeled(server, "left")
    [right] = labeled(server, "right")
    children = Server.children(server)
    assert {:ok, work} = Example.work_signal(%{value: 2})
    assert {:ok, _, [_]} = Server.call(server, work)
    eventually(fn -> Server.agent(left).state.total == 2 end)
    assert {:ok, redirect} = Example.redirect_signal(%{value: 5})
    assert {:ok, _, _} = Server.call(server, redirect)
    assert :ok = Server.await_ready(server)
    eventually(fn -> Server.agent(right).state.total == 5 end)
    assert Server.agent(left).state.total == 2
    assert Server.children(server) == children

    before = Server.snapshot(server)
    assert {:error, _} = Server.call(server, redirect)
    assert Server.snapshot(server) == before

    assert {:ok, fanout} = Example.fanout_signal()
    assert {:ok, _, _} = Server.call(server, fanout)
    assert :ok = Server.await_ready(server)
    assert {:ok, _, [_]} = Server.call(server, work)

    eventually(fn ->
      Server.agent(left).state.total == 4 and Server.agent(right).state.total == 7
    end)

    assert Server.children(server) == children
    stop_topology(server)
  end

  @tag :tmp_dir
  test "thaw restores changed connections and routes new outputs to the saved destination", %{
    jido: jido,
    tmp_dir: path
  } do
    persistence = {Jido.Persistence.File, path: path}
    id = unique_id("saved-connections")

    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, Example, id: id, persistence: persistence)

    assert {:ok, redirect} = Example.redirect_signal(%{value: 5})
    assert {:ok, accepted, _} = Server.call(server, redirect)
    assert :ok = Server.await_ready(server)
    [right] = labeled(server, "right")
    eventually(fn -> Server.agent(right).state.total == 5 end)
    assert accepted.topology.connections != Example.definition().topology.connections
    snapshot = Server.snapshot(server)
    assert {:ok, portable} = Jido.Persistence.snapshot(snapshot.agent)
    monitors = monitor_runtime(Server.activation(server))
    assert :ok = Jido.hibernate(jido, server)
    assert_down(monitors)
    assert {:ok, restored} = Jido.thaw(jido, Example, id, persistence: persistence)
    assert :ok = Server.await_ready(restored)
    assert Server.snapshot(restored).state_version == snapshot.state_version
    assert {:ok, ^portable} = Jido.Persistence.snapshot(Server.agent(restored))
    [left] = labeled(restored, "left")
    [right] = labeled(restored, "right")
    assert Server.agent(right).state.total == 5
    assert {:ok, work} = Example.work_signal(%{value: 4})
    assert {:ok, _, [_]} = Server.call(restored, work)
    eventually(fn -> Server.agent(right).state.total == 9 end)
    assert Server.agent(left).state.total == 0
    stop_topology(restored)
    assert Jido.agent_count(jido) == 0
  end
end
