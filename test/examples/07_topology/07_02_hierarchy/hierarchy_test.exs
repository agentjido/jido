defmodule Jido.Examples.Topology.HierarchyTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.Topology.Hierarchy
  alias Jido.Topology.Controller

  test "starts the complete logical tree", %{jido: jido} do
    controller =
      start_supervised!(
        {Controller, jido: jido, topology: Hierarchy.new!(id: "hierarchy-example")}
      )

    assert :ok = Controller.await_ready(controller)
    leader = Controller.whereis_agent(controller, :leader)
    assert map_size(Jido.AgentServer.children(leader)) == 3
    assert Jido.agent_count(jido) == 5
  end
end
