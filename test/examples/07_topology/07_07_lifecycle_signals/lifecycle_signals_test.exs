defmodule Jido.Examples.Topology.LifecycleSignalsTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{Cell, LifecycleSignals}
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

  test "records degraded activation and successful manual repair", %{jido: jido} do
    topology_id = unique_id("lifecycle-degraded")
    instance = LifecycleSignals.new!(id: topology_id)
    worker_id = instance.plan.agents["agent/worker"].id

    {:ok, control} =
      Jido.start_agent(jido, LifecycleSignals, id: unique_id("lifecycle-control"))

    {:ok, conflict} = Jido.start_agent(jido, Cell, id: worker_id)

    controller =
      start_supervised!(
        {Controller, jido: jido, topology: instance, lifecycle: control, repair: :manual}
      )

    eventually(fn ->
      status = Controller.status(controller)
      events = AgentServer.agent(control).state.events

      status.status == :degraded and
        status.errors == %{"agent/worker" => :agent_identity_in_use} and
        "jido.topology.lifecycle.component.failed" in events and
        "jido.topology.lifecycle.status.changed" in events
    end)

    assert :ok = AgentServer.stop(conflict)
    assert :ok = Controller.reconcile(controller)
    assert :ok = Controller.await_ready(controller)

    eventually(fn ->
      "jido.topology.lifecycle.component.ready" in AgentServer.agent(control).state.events
    end)

    worker = Controller.whereis_agent(controller, :worker)
    assert is_pid(worker)
    stop_topology(controller, [worker])
    assert Process.alive?(control)
    monitors = monitor_runtime([control])
    assert :ok = AgentServer.stop(control)
    assert_down(monitors)
    assert Jido.agent_count(jido) == 0
  end
end
