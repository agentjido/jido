defmodule Jido.Examples.Topology.LifecycleSignalsTest do
  use JidoTest.Case, async: true
  @moduletag :example

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
  end
end
