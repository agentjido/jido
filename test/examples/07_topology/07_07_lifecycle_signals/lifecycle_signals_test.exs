defmodule Jido.Examples.Topology.LifecycleSignalsTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Topology.LifecycleSignals
  alias Jido.Topology.Controller

  test "a normal Agent route receives topology lifecycle Signals", %{jido: jido} do
    {:ok, control} = Jido.start_agent(jido, LifecycleSignals, id: "lifecycle-control")
    instance = LifecycleSignals.new!(id: "lifecycle-example")

    controller =
      start_supervised!(
        {Controller, jido: jido, topology: instance, lifecycle: control, repair: :manual}
      )

    assert :ok = Controller.await_ready(controller)

    eventually(fn ->
      events = AgentServer.agent(control).state.events

      "jido.topology.lifecycle.operation.started" in events and
        "jido.topology.lifecycle.component.ready" in events and
        "jido.topology.lifecycle.operation.completed" in events
    end)

    worker = Controller.whereis_agent(controller, :worker)
    stop_topology(controller, [worker])
    assert Jido.whereis_agent(jido, "lifecycle-control") == control
    assert AgentServer.agent(control).id == "lifecycle-control"
    assert Jido.agent_count(jido) == 1
    monitors = monitor_runtime([control])
    assert :ok = AgentServer.stop(control)
    assert_down(monitors)
    assert Jido.agent_count(jido) == 0
  end
end
