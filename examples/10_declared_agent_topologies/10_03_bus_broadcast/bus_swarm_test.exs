Code.require_file("../support/cell.ex", __DIR__)
Code.require_file("swarm.ex", __DIR__)
Code.require_file("../support/runtime.ex", __DIR__)

defmodule Jido.Examples.Topology.BusSwarmTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{Runtime, Swarm}

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"topology_bus_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "a local Bus broadcasts a work output to every counted member", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Swarm, 4)
    workers = Runtime.members(instance, root)
    assert length(workers) == 3
    assert {:ok, signal} = Swarm.work_signal(%{value: 5})
    assert {:ok, %{status: :committed}} = AgentServer.call(root, signal)
    assert AgentServer.snapshot(root).agent.state.sent == 1

    assert Runtime.eventually(fn ->
             Enum.all?(workers, &(AgentServer.snapshot(&1).agent.state.total == 5))
           end)

    assert Enum.all?(workers, &(AgentServer.snapshot(&1).agent_revision == 1))
    assert :ok = Runtime.stop(instance, root)
  end

  test "stopping the owner stops its Bus runtime and member tree", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Swarm, 4)
    assert length(Runtime.members(instance, root)) == 3
    assert :ok = Runtime.stop(instance, root)
    assert Jido.resident_agent_count(instance) == 0
  end
end
