defmodule JidoTest.Examples.MultiAgent.ChildLifecycleTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :multi_agent
  alias Jido.Examples.{ChildLifecycle, Worker}

  test "pure evaluation plans a child; only live dispatch starts it", %{jido: jido} do
    parent = start_agent!(jido, ChildLifecycle)
    before = Server.snapshot(parent)

    {:ok, command_signal_1} = ChildLifecycle.start_worker_signal(%{tag: "worker"})

    assert {:ok, candidate, [%Jido.Agent.Directive.SpawnChild{tag: "worker"}]} =
             ChildLifecycle.cmd(
               before.agent,
               command_signal_1
             )

    assert candidate.state.desired == ["worker"]
    assert Server.children(parent) == %{}
    assert Server.snapshot(parent) == before

    {:ok, route_signal_1} = ChildLifecycle.start_worker_signal(%{tag: "worker"})

    assert {:ok, _} =
             Jido.AgentServer.call(parent, route_signal_1, [])

    child = eventually(fn -> Server.children(parent)["worker"] end)
    assert child.id == "#{before.agent.id}/worker"
    assert Jido.whereis_agent(jido, child.id) == child.pid
    assert Server.status(child.pid).runtime.parent.id == before.agent.id
    assert state(parent) == %{desired: ["worker"]}

    {:ok, route_signal_2} = ChildLifecycle.start_worker_signal(%{tag: "worker"})

    assert {:error, _} =
             Jido.AgentServer.call(parent, route_signal_2, [])

    assert Server.children(parent)["worker"].pid == child.pid
  end

  test "abnormal restart keeps committed child state and updates the tracked PID", %{jido: jido} do
    parent = start_agent!(jido, ChildLifecycle)

    {:ok, route_signal_3} = ChildLifecycle.start_worker_signal(%{tag: "worker"})

    assert {:ok, _} =
             Jido.AgentServer.call(parent, route_signal_3, [])

    first = Server.children(parent)["worker"]

    {:ok, route_signal_4} =
      Worker.calculate_signal(%{
        request_id: "r",
        job_id: "j",
        tag: "worker",
        value: 3
      })

    assert {:ok, committed} =
             Jido.AgentServer.call(first.pid, route_signal_4, [])

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

    {:ok, route_signal_5} = ChildLifecycle.start_worker_signal(%{tag: "first"})

    assert {:ok, _} =
             Jido.AgentServer.call(parent, route_signal_5, [])

    first = Server.children(parent)["first"]
    ref = Process.monitor(first.pid)

    {:ok, route_signal_6} = ChildLifecycle.stop_worker_signal(%{tag: "first"})

    assert {:ok, _} =
             Jido.AgentServer.call(parent, route_signal_6, [])

    assert_receive {:DOWN, ^ref, :process, _, _}, 1000
    eventually(fn -> Server.children(parent) == %{} end)

    {:ok, route_signal_7} = ChildLifecycle.start_worker_signal(%{tag: "second"})

    assert {:ok, _} =
             Jido.AgentServer.call(parent, route_signal_7, [])

    second = Server.children(parent)["second"]
    ref = Process.monitor(second.pid)
    assert :ok = Jido.stop_agent(jido, parent)
    assert_receive {:DOWN, ^ref, :process, _, _}, 1000
    eventually(fn -> Jido.whereis_agent(jido, second.id) == nil end)
  end
end
