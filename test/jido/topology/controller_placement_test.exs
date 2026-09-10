defmodule JidoTest.Topology.ControllerPlacementTest do
  use JidoTest.PeerCase, async: false

  alias Jido.Examples.Topology.Cell
  alias Jido.Topology.{Builder, Controller}

  test "starts and moves an Agent on exact connected nodes", c do
    id = "placed-#{System.unique_integer([:positive])}"

    instance =
      Builder.new(name: "placed_topology")
      |> Builder.agent(:worker, Cell, node: c.node_b)
      |> Builder.build!(id: id)

    assert {:ok, controller} =
             peer_call(c.peer_a, Supervisor, :start_child, [
               Jido.Supervisor,
               {Controller, jido: c.jido, topology: instance, repair: :manual}
             ])

    assert :ok = peer_call(c.peer_a, Controller, :await_ready, [controller])
    first = peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])
    assert is_pid(first)
    assert node(first) == c.node_b

    assert :ok =
             peer_call(c.peer_a, Controller, :place_agent, [controller, :worker, c.node_a])

    assert :ok = peer_call(c.peer_a, Controller, :await_ready, [controller])
    second = peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])
    assert is_pid(second)
    assert second != first
    assert node(second) == c.node_a
    assert c.node_a == peer_call(c.peer_a, Controller, :agent_node, [controller, :worker])

    children = peer_call(c.peer_a, Supervisor, :which_children, [controller])

    {_, runtime, _, _} =
      Enum.find(children, &(elem(&1, 0) == Jido.Topology.Controller.Runtime))

    :ok = peer_call(c.peer_a, GenServer, :stop, [runtime, :worker_crash])
    assert :ok = peer_call(c.peer_a, Controller, :await_ready, [controller])
    assert second == peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])
    assert c.node_a == peer_call(c.peer_a, Controller, :agent_node, [controller, :worker])

    assert :ok =
             peer_call(c.peer_a, Supervisor, :terminate_child, [
               Jido.Supervisor,
               {Controller, id}
             ])
  end
end
