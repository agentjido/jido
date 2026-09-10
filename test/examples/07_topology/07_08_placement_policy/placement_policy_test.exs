defmodule Jido.Examples.Topology.PlacementPolicyTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.AgentServer
  alias Jido.Examples.Topology.PlacementPolicy
  alias Jido.Topology.Controller

  test "a control route delegates exact placement to its Plugin", %{jido: jido} do
    topology_id = "placement-policy-example"
    {:ok, control} = Jido.start_agent(jido, PlacementPolicy, id: "placement-control")
    instance = PlacementPolicy.new!(id: topology_id)

    controller =
      start_supervised!(
        {Controller, jido: jido, topology: instance, lifecycle: control, repair: :manual}
      )

    assert :ok = Controller.await_ready(controller)
    worker = Controller.whereis_agent(controller, :workers, 1)

    assert {:ok, _agent} = PlacementPolicy.place(control, topology_id, :workers, 1, node())
    assert Controller.agent_node(controller, :workers, 1) == node()
    assert Controller.whereis_agent(controller, :workers, 1) == worker
    eventually(fn -> AgentServer.agent(control).state.lifecycle_events > 0 end)
  end
end
