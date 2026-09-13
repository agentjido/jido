defmodule Jido.Examples.Topology.PluginContributionTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{InboxWorker, InvalidPluginContribution, PluginContribution}
  alias Jido.Signal.Bus
  alias Jido.Topology.Controller

  test "plans and starts a Bus contributed by an Agent Plugin", %{jido: jido} do
    definition = PluginContribution.topology()
    assert definition.resources == []
    assert definition.connections == []

    instance = PluginContribution.new!(id: "plugin-contribution-example")
    assert Map.has_key?(instance.plan.resources, "bus/inbox")

    assert instance.plan.agents["agent/worker"].subscriptions == [
             %{bus: "bus/inbox", path: "examples.topology.plugin_contribution.work"}
           ]

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)

    worker = Controller.whereis_agent(controller, :worker)
    bus = Controller.whereis_bus(controller, :inbox)
    assert is_pid(worker)
    assert is_pid(bus)
    assert {:ok, [_record]} = Bus.publish(bus, [InboxWorker.work_signal!(5)])
    eventually(fn -> AgentServer.agent(worker).state.total == 5 end)
  end

  test "invalid Plugin resources stop planning before activation", %{jido: jido} do
    assert Jido.agent_count(jido) == 0

    assert {:error, %Jido.Error.ValidationError{} = error} =
             InvalidPluginContribution.new(id: "invalid-plugin-contribution")

    assert error.message == "Topology keys must be nonempty strings or atoms"
    assert Jido.agent_count(jido) == 0
  end
end
