Code.require_file("../support/cell.ex", __DIR__)
Code.require_file("hierarchy.ex", __DIR__)
Code.require_file("../support/runtime.ex", __DIR__)

defmodule Jido.Examples.Topology.HierarchyTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{Cell, Hierarchy, Runtime}

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"topology_hierarchy_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "a nested definition starts its own declared members", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Hierarchy, 4)
    assert [{_team_id, _team}] = Runtime.named(instance, "topology_team")
    workers = Runtime.labeled(instance, root, "worker")
    assert length(workers) == 2

    [first, second] = workers
    before = AgentServer.snapshot(second)
    assert {:ok, work} = Cell.work_signal(%{value: 3})
    assert {:ok, %{status: :committed}} = AgentServer.call(first, work)
    assert AgentServer.snapshot(first).agent.state.total == 3
    assert AgentServer.snapshot(second) == before
    assert :ok = Runtime.stop(instance, root)
  end

  test "one failed worker restarts without replacing its sibling team", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Hierarchy, 4)
    [{first_id, first}, {second_id, second}] = worker_records(instance)

    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, :killed}, 1_000

    replacement =
      Runtime.eventually(fn ->
        case Enum.find(worker_records(instance), fn {id, _pid} -> id == first_id end) do
          {^first_id, pid} when pid != first -> pid
          _other -> nil
        end
      end)

    assert is_pid(replacement)
    assert :ok = AgentServer.await_ready(replacement)
    assert {second_id, second} in worker_records(instance)
    assert Process.alive?(second)
    assert :ok = Runtime.stop(instance, root)
  end

  test "a root snapshot stores topology intent but not current member state", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Hierarchy, 4)
    [worker | _rest] = Runtime.labeled(instance, root, "worker")
    assert {:ok, work} = Cell.work_signal(%{value: 9})
    assert {:ok, %{status: :committed}} = AgentServer.call(worker, work)
    assert AgentServer.snapshot(worker).agent.state.total == 9

    root_snapshot = AgentServer.snapshot(root)
    assert root_snapshot.agent.state == %{}
    assert length(root_snapshot.agent.topology.agents) == 1
    assert {:ok, portable} = Jido.Persistence.snapshot(root_snapshot.agent)
    assert {:ok, restored_root} = Jido.Persistence.restore(portable)
    assert restored_root.state == %{}
    assert :ok = Runtime.stop(instance, root)
  end

  test "stopping the root stops its complete static subtree", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Hierarchy, 4)
    assert :ok = Runtime.stop(instance, root)
    assert Jido.resident_agent_count(instance) == 0
  end

  defp worker_records(instance) do
    for {id, pid} <- Runtime.residents(instance),
        %{agent: %{name: "topology_cell", state: %{label: "worker"}}} <- [AgentServer.snapshot(pid)],
        do: {id, pid}
  end
end
