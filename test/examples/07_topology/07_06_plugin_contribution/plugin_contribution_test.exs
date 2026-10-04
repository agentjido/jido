defmodule Jido.Examples.Topology.PluginContributionTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{InboxWorker, InvalidPluginContribution, PluginContribution}
  alias Jido.Signal.Bus
  alias Jido.Topology.Controller

  test "applies one contributed relationship to all helper group members", %{
    jido: jido
  } do
    definition = PluginContribution.topology()
    assert definition.resources == []
    assert definition.relationships == []
    assert definition.connections == []

    instance = PluginContribution.new!(id: "plugin-contribution-example")
    assert Map.has_key?(instance.plan.resources, "bus/inbox")

    for member <- 1..2 do
      helper = instance.plan.agents["group/helpers/#{member}"]
      assert helper.parent == "agent/worker"
      assert helper.on_parent_exit == :stop
    end

    assert instance.plan.agents["agent/worker"].subscriptions == [
             %{bus: "bus/inbox", path: "examples.topology.plugin_contribution.work"}
           ]

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)

    worker = Controller.whereis_agent(controller, :worker)
    helpers = for member <- 1..2, do: Controller.whereis_agent(controller, :helpers, member)
    bus = Controller.whereis_bus(controller, :inbox)
    assert is_pid(worker)
    assert Enum.all?(helpers, &is_pid/1)

    assert worker
           |> AgentServer.children()
           |> Map.values()
           |> Enum.count(&(&1.kind == :agent)) == 2

    assert is_pid(bus)

    assert {:ok, work} = InboxWorker.work_signal(%{value: 5})
    assert {:ok, [_]} = Bus.publish(bus, [work])

    eventually(fn -> AgentServer.agent(worker).state.total == 5 end)
    assert AgentServer.snapshot(worker).state_version == 1
    assert PluginContribution.topology() == definition
    stop_topology(controller, [worker | helpers], [bus])
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
