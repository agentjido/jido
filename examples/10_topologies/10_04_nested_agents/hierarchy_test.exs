Code.require_file("../support/cell.ex", __DIR__)
Code.require_file("hierarchy.ex", __DIR__)

defmodule Jido.Examples.Topology.HierarchyTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  import Jido.Test.AgentServer.TopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, Hierarchy}

  test "a nested definition starts its own declared members", %{jido: jido} do
    server = start_topology(jido, Hierarchy)
    [team] = members(server)
    workers = members(team)
    assert length(workers) == 2
    assert Jido.agent_count(jido) == 4

    [first, second] = workers
    before = Server.snapshot(second)
    assert {:ok, work} = Cell.work_signal(%{value: 3})
    assert {:ok, changed, []} = Server.call(first, work)
    assert changed.state.total == 3
    assert Server.snapshot(second) == before
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end

  test "stopping the root stops its complete static subtree", %{jido: jido} do
    server = start_topology(jido, Hierarchy)
    [team] = members(server)
    monitors = monitor_runtime(Server.activation(team))
    stop_topology(server)
    assert_down(monitors)
    assert Jido.agent_count(jido) == 0
  end
end
