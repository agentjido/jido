defmodule JidoTest.Topology.ControllerPlacementTest do
  use JidoTest.PeerCase, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Cell
  alias Jido.Topology.Controller

  test "starts and moves an Agent on exact connected nodes", c do
    id = "placed-#{System.unique_integer([:positive])}"

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "placed_topology",
                 agents: [%{key: :worker, module: Cell, node: c.node_b}]
               }) do
          Jido.Topology.instantiate(definition, id: id)
        end
      )

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

  test "Hibernate cleans a placed member and Thaw restores it on its accepted node", c do
    id = "placed-hibernate-#{System.unique_integer([:positive])}"

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 name: "placed_hibernate",
                 agents: [%{key: :worker, module: Cell, node: c.node_b}]
               }) do
          Jido.Topology.instantiate(definition, id: id)
        end
      )

    assert {:ok, controller} =
             peer_call(c.peer_a, Supervisor, :start_child, [
               Jido.Supervisor,
               {Controller, jido: c.jido, topology: instance, repair: :manual}
             ])

    assert :ok = peer_call(c.peer_a, Controller, :await_ready, [controller])
    original = peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])
    assert is_pid(original)
    assert node(original) == c.node_b
    {:ok, signal} = Cell.work_signal(%{value: 4})
    assert {:ok, %{state: %{total: 4}}} = peer_call(c.peer_a, Server, :call, [original, signal])

    assert :ok = peer_call(c.peer_a, Controller, :hibernate, [controller, :worker])
    assert nil == peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])
    assert nil == peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, "#{id}/agent/worker"])

    assert %{member_statuses: %{"agent/worker" => :hibernated}} =
             peer_call(c.peer_a, Controller, :status, [controller])

    assert :ok = peer_call(c.peer_a, Controller, :thaw, [controller, :worker])
    restored = peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])
    assert is_pid(restored)
    assert restored != original
    assert node(restored) == c.node_b
    assert peer_call(c.peer_a, Server, :agent, [restored]).state.total == 4

    assert :ok =
             peer_call(c.peer_a, Supervisor, :terminate_child, [
               Jido.Supervisor,
               {Controller, id}
             ])
  end
end
