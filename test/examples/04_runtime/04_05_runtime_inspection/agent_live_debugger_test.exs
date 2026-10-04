defmodule JidoTest.Examples.Runtime.InspectionFixture do
  @moduledoc false

  use Jido.Agent, name: "test_runtime_inspection"

  agent do
    schema Zoi.object(%{
             status: Zoi.string() |> Zoi.default("idle"),
             secret_token: Zoi.string() |> Zoi.default("hidden"),
             result: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/test/runtime_inspection"

    route "test.runtime.inspect", as: :record_result do
      action %{result: result},
        schema: Zoi.object(%{result: Zoi.string()}),
        context: context do
        JidoTest.Examples.RuntimeBarrier.wait()
        {:ok, %{context.agent_state | status: "complete", result: result}}
      end
    end
  end
end

defmodule JidoTest.Examples.Runtime.AgentLiveDebuggerTest do
  use JidoTest.FeatureSDKCase

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.Examples.AgentLiveDebugger
  alias Jido.Plugin.Scheduler
  alias JidoTest.Examples.Runtime.InspectionFixture
  alias JidoTest.Examples.RuntimeBarrier

  setup do
    start_supervised!(RuntimeBarrier)
    :ok = RuntimeBarrier.arm(self())
    :ok
  end

  test "a snapshot uses public inspection and removes secrets", %{jido: jido} do
    agent =
      start_agent!(jido, AgentLiveDebugger,
        initial_state: %{secret_token: "secret"},
        debug_max_events: 2
      )

    {:ok, route_signal_1} = AgentLiveDebugger.record_result_signal(%{result: "done"})

    assert {:ok, _} =
             Jido.AgentServer.call(agent, route_signal_1, [])

    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.agent_module == AgentLiveDebugger
    assert snapshot.state == %{status: "complete", result: "done"}
    assert snapshot.state_version == 1
    assert snapshot.runtime_status == :idle
    assert snapshot.active == nil
    assert snapshot.scheduler == %{cron: %{}}

    assert %{{:plugin, Scheduler} => %{module: Scheduler, kind: :plugin, pid: runtime}} =
             snapshot.children

    assert is_pid(runtime)
    refute inspect(snapshot) =~ "secret"
  end

  test "inspection reads the committed state while an Action is still running", %{jido: jido} do
    agent = start_agent!(jido, InspectionFixture)

    task =
      Task.async(fn ->
        {:ok, route_signal_2} = InspectionFixture.record_result_signal(%{result: "later"})
        Jido.AgentServer.call(agent, route_signal_2)
      end)

    assert_receive :runtime_barrier_waiting, 1_000
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state == %{status: "idle", result: ""}
    assert snapshot.state_version == 0
    refute snapshot.runtime_status == :idle
    assert :ok = RuntimeBarrier.release()
    assert {:ok, _} = Task.await(task)
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state.result == "later"
    assert snapshot.state_version == 1
  end

  test "the debug buffer is explicit, bounded, and safe", %{jido: jido} do
    agent =
      start_agent!(jido, AgentLiveDebugger,
        initial_state: %{secret_token: "debug-secret"},
        debug_max_events: 2
      )

    assert {:error, :debug_not_enabled} = Server.recent_events(agent)
    assert :ok = Server.set_debug(agent, true)

    for result <- ["one", "two"] do
      {:ok, signal} = AgentLiveDebugger.record_result_signal(%{result: result})
      assert {:ok, _agent} = Server.call(agent, signal)
    end

    assert {:ok, events} = Server.recent_events(agent, limit: 10)
    assert length(events) == 2
    assert Enum.map(events, & &1.event) == [:turn_completed, :turn_committed]
    refute inspect(events) =~ "debug-secret"
    refute Enum.any?(events, &Map.has_key?(&1, :server_state))

    assert :ok = Server.set_debug(agent, false)
    assert {:error, :debug_not_enabled} = Server.recent_events(agent)
  end
end
