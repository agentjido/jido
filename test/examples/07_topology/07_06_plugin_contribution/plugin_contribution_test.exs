defmodule Jido.Examples.Topology.PluginContributionTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{InboxWorker, InvalidPluginContribution, PluginContribution}
  alias Jido.Signal.Bus
  alias Jido.Topology.Controller

  test "restores a contributed subscription and committed state after Agent restart", %{
    jido: jido
  } do
    definition = PluginContribution.topology()
    assert definition.resources == []
    assert definition.connections == []

    instance = PluginContribution.new!(id: "plugin-contribution-example")
    assert Map.has_key?(instance.plan.resources, "bus/inbox")

    assert instance.plan.agents["agent/worker"].subscriptions == [
             %{bus: "bus/inbox", path: "examples.topology.plugin_contribution.work"}
           ]

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)

    worker = Controller.whereis_agent(controller, :worker)
    bus = Controller.whereis_bus(controller, :inbox)
    assert is_pid(worker)
    assert is_pid(bus)

    assert {:ok, work} = InboxWorker.work_signal(%{value: 5})
    assert {:ok, [_]} = Bus.publish(bus, [work])

    eventually(fn -> AgentServer.agent(worker).state.total == 5 end)
    committed = AgentServer.agent(worker)
    monitors = monitor_runtime([worker])
    Process.exit(worker, :kill)
    assert_down(monitors)
    assert :ok = Controller.await_ready(controller)
    replacement = Controller.whereis_agent(controller, :worker)
    assert is_pid(replacement) and replacement != worker
    assert AgentServer.agent(replacement) == committed
    assert AgentServer.snapshot(replacement).state_version == 1
    assert Controller.whereis_bus(controller, :inbox) == bus

    assert {:ok, work} = InboxWorker.work_signal(%{value: 2})
    assert {:ok, [_]} = Bus.publish(bus, [work])
    eventually(fn -> AgentServer.snapshot(replacement).state_version == 2 end)
    assert AgentServer.agent(replacement).state == %{total: 7}
    assert PluginContribution.topology() == definition
    stop_topology(controller, [replacement], [bus])
    assert Jido.agent_count(jido) == 0
  end

  test "invalid Plugin resources stop planning before activation", %{jido: jido} do
    assert Jido.agent_count(jido) == 0

    assert {:error, %Jido.Error.ValidationError{} = error} =
             InvalidPluginContribution.new(id: "invalid-plugin-contribution")

    assert error.message == "Topology keys must be nonempty strings or atoms"
    assert Jido.agent_count(jido) == 0
  end
end
