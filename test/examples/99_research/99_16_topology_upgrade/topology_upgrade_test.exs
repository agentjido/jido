defmodule JidoTest.Examples.TopologyUpgradeTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.Topology.Cell
  alias Jido.Examples.TopologyUpgrade, as: Example
  alias Jido.Topology.Controller
  alias Jido.AgentServer, as: Server

  defmodule PersistentJido do
    use Jido, otp_app: :jido, persistence: {Jido.Persistence.ETS, table: __MODULE__}
  end

  test "pure plans identify additions, removals, changed definitions, and retained Agents" do
    {:ok, old} = Example.build("team", 3)
    {:ok, larger} = Example.build("team", 5)
    {:ok, smaller} = Example.build("team", 1)
    {:ok, revised} = Example.build("team", 3, Example.WorkerV2)

    assert {:ok, growth} = Example.diff(old, larger)
    assert growth.added == ["group/workers/4", "group/workers/5"]
    assert growth.removed == []
    assert growth.changed == []
    assert length(growth.unchanged) == 4

    assert {:ok, shrink} = Example.diff(old, smaller)
    assert shrink.removed == ["group/workers/2", "group/workers/3"]
    assert {:ok, upgrade} = Example.diff(old, revised)
    assert upgrade.changed == ["group/workers/1", "group/workers/2", "group/workers/3"]
    assert upgrade.unchanged == ["agent/observer"]

    {:ok, another} = Example.build("another-team", 3)
    assert {:error, :topology_identity_mismatch} = Example.diff(old, another)
  end

  test "invalid target validation has no effect on a running topology", c do
    {instance, controller} = start_team(c.jido)
    workers = worker_pids(controller, 3)
    assert {:ok, _} = Cell.work(hd(workers), 7)
    assert {:error, _} = Example.build(instance.id, -1)
    assert worker_pids(controller, 3) == workers
    assert Server.agent(hd(workers)).state.total == 7
  end

  test "the target worker definition changes executed behavior", c do
    {:ok, target} = Example.build(unique_id("revision-two"), 3, Example.WorkerV2)
    controller = start_supervised!({Controller, jido: c.jido, topology: target})
    assert :ok = Controller.await_ready(controller)
    worker = Controller.whereis_agent(controller, :workers, 1)
    assert {:ok, agent} = Cell.work(worker, 2)
    assert agent.state.total == 20
    assert agent.state.received == 1
    assert Server.agent(Controller.whereis_agent(controller, :observer)).state.total == 0
  end

  test "full controller replacement can grow the topology and restore saved worker state" do
    start_supervised!(PersistentJido)
    {instance, controller} = start_team(PersistentJido)
    old_workers = worker_pids(controller, 3)
    observer = Controller.whereis_agent(controller, :observer)
    assert {:ok, _} = Cell.work(hd(old_workers), 7)
    monitors = Map.new([observer | old_workers], &{Process.monitor(&1), &1})
    stop_supervised!({Controller, instance.id})

    for {monitor, pid} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    end

    {:ok, target} = Example.build(instance.id, 5)
    replacement = start_supervised!({Controller, jido: PersistentJido, topology: target})
    assert :ok = Controller.await_ready(replacement)
    new_workers = worker_pids(replacement, 5)
    assert Enum.all?(new_workers, &is_pid/1)
    assert Enum.all?(new_workers, &(&1 not in old_workers))
    assert Controller.whereis_agent(replacement, :observer) != observer
    assert Server.agent(hd(new_workers)).state.total == 7
    assert {:ok, agent} = Cell.work(hd(new_workers), 2)
    assert agent.state.total == 9
  end

  test "a live target grows three workers to five while unchanged Agents retain PID and state",
       c do
    {instance, controller} = start_team(c.jido)
    old_workers = worker_pids(controller, 3)
    observer = Controller.whereis_agent(controller, :observer)
    assert {:ok, _} = Cell.work(hd(old_workers), 7)
    {:ok, target} = Example.build(instance.id, 5)

    # Current public startup is the available submission path. It rejects this
    # target as already_started. An explicit live-update API is required.
    assert {:ok, updated} = Controller.start_link(jido: c.jido, topology: target)
    assert :ok = Controller.await_ready(updated)
    assert worker_pids(updated, 3) == old_workers
    assert Controller.whereis_agent(updated, :observer) == observer
    assert Enum.all?(worker_pids(updated, 5), &is_pid/1)
    assert Server.agent(hd(old_workers)).state.total == 7
  end

  defp start_team(jido) do
    {:ok, instance} = Example.build(unique_id("upgrade-team"), 3)
    controller = start_supervised!({Controller, jido: jido, topology: instance})
    :ok = Controller.await_ready(controller)
    {instance, controller}
  end

  defp worker_pids(controller, count),
    do: Enum.map(1..count, &Controller.whereis_agent(controller, :workers, &1))
end
