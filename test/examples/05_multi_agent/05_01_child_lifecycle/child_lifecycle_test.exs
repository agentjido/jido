defmodule JidoTest.Examples.MultiAgent.ChildLifecycleTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :multi_agent
  alias Jido.Examples.{ChildLifecycle, Worker}

  test "pure evaluation plans a child; only live dispatch starts it", %{jido: jido} do
    parent = start_agent!(jido, ChildLifecycle)
    before = Server.snapshot(parent)

    assert {:ok, candidate, [%Jido.Agent.Directive.SpawnAgent{tag: "worker"}]} =
             ChildLifecycle.cmd(before.agent, ChildLifecycle.start_worker_signal!("worker"))

    assert candidate.state.desired == ["worker"]
    assert Server.children(parent) == %{}
    assert Server.snapshot(parent) == before
    assert {:ok, _} = ChildLifecycle.start_worker(parent, "worker")
    child = eventually(fn -> Server.children(parent)["worker"] end)
    assert child.id == "#{before.agent.id}/worker"
    assert Jido.whereis_agent(jido, child.id) == child.pid
    assert Server.status(child.pid).runtime.parent.id == before.agent.id
    assert state(parent) == %{desired: ["worker"]}
    assert {:error, _} = ChildLifecycle.start_worker(parent, "worker")
    assert Server.children(parent)["worker"].pid == child.pid
  end

  test "abnormal restart keeps committed child state and updates the tracked PID", %{jido: jido} do
    parent = start_agent!(jido, ChildLifecycle)
    assert {:ok, _} = ChildLifecycle.start_worker(parent, "worker")
    first = Server.children(parent)["worker"]
    assert {:ok, committed} = Worker.calculate(first.pid, "r", "j", "worker", 3)
    Process.exit(first.pid, :kill)

    next =
      eventually(fn ->
        case Server.children(parent)["worker"] do
          %{pid: pid} = child when pid != first.pid -> child
          _ -> nil
        end
      end)

    assert next.id == first.id
    assert Server.snapshot(next.pid).agent.state == committed.state
    assert Server.snapshot(next.pid).state_version == 1
  end

  test "explicit child stop and parent stop remove owned processes", %{jido: jido} do
    parent = start_agent!(jido, ChildLifecycle)
    assert {:ok, _} = ChildLifecycle.start_worker(parent, "first")
    first = Server.children(parent)["first"]
    ref = Process.monitor(first.pid)
    assert {:ok, _} = ChildLifecycle.stop_worker(parent, "first")
    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
    eventually(fn -> Server.children(parent) == %{} end)
    assert {:ok, _} = ChildLifecycle.start_worker(parent, "second")
    second = Server.children(parent)["second"]
    ref = Process.monitor(second.pid)
    assert :ok = Jido.stop_agent(jido, parent)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
    eventually(fn -> Jido.whereis_agent(jido, second.id) == nil end)
  end
end
