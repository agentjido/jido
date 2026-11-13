Code.require_file("cell.ex", __DIR__)
Code.require_file("independent.ex", __DIR__)
Code.require_file("../support/runtime.ex", __DIR__)

defmodule Jido.Examples.Topology.IndependentTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Topology.Independent
  alias Jido.Examples.Topology.Independent.Cell
  alias Jido.Examples.Topology.Runtime

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"topology_independent_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "a JSON definition starts the same declared members", %{instance: instance} do
    definition = Independent.definition()
    catalog = Independent.registry()
    assert {:ok, document} = Jido.Codec.encode(definition, catalog: catalog, codec: Jido.Agent.Codec)

    assert {:ok, decoded} =
             Jido.Codec.decode(
               JSON.decode!(JSON.encode!(document)),
               catalog: catalog,
               codec: Jido.Agent.Codec
             )

    assert decoded == definition
    assert {:ok, root} = Runtime.start(instance, decoded, 3)

    assert Enum.sort(Enum.map(Runtime.members(instance, root), &AgentServer.snapshot(&1).agent.state.label)) ==
             ["left", "right"]

    [left] = Runtime.labeled(instance, root, "left")
    assert {:ok, schedule} = Cell.schedule_signal(%{value: 4})
    assert {:ok, %{status: :committed}} = AgentServer.call(left, schedule)
    assert Runtime.eventually(fn -> AgentServer.snapshot(left).agent.state.total == 4 end)
    assert AgentServer.snapshot(left).agent.state.received == 1
    assert :ok = Runtime.stop(instance, root)
  end

  test "named members keep separate initial and committed state", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Independent, 3)
    [left] = Runtime.labeled(instance, root, "left")
    [right] = Runtime.labeled(instance, root, "right")
    before = AgentServer.snapshot(right)

    assert {:ok, work} = Cell.work_signal(%{value: 4})
    assert {:ok, %{status: :committed}} = AgentServer.call(left, work)

    assert Map.take(AgentServer.snapshot(left).agent.state, [:label, :received, :total]) == %{
             label: "left",
             received: 1,
             total: 4
           }

    assert AgentServer.snapshot(right) == before
    assert :ok = Runtime.stop(instance, root)
    assert Jido.resident_agent_count(instance) == 0
  end

  test "stopping the owner stops all member runtimes", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Independent, 3)
    assert length(Runtime.members(instance, root)) == 2
    assert :ok = Runtime.stop(instance, root)
    assert Jido.resident_agent_count(instance) == 0
  end
end
