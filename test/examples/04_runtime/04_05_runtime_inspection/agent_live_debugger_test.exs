defmodule JidoTest.Examples.Runtime.InspectionFixture do
  @moduledoc false

  use Jido.Agent, name: "test_runtime_inspection"

  agent do
    schema Zoi.object(%{
             status: Zoi.string() |> Zoi.default("idle"),
             secret_token: Zoi.string() |> Zoi.default("hidden"),
             result: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/test/runtime_inspection"

    route "test.runtime.inspect" do
      action %{result: result}, context: context do
        context.inspection_barrier.()
        {:ok, %{context.agent_state | status: "complete", result: result}}
      end

      define :record_result
    end
  end
end

defmodule JidoTest.Examples.Runtime.AgentLiveDebuggerTest do
  use JidoTest.FeatureSDKCase

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.Examples.AgentLiveDebugger
  alias JidoTest.Examples.Runtime.InspectionFixture

  test "a snapshot uses public inspection and removes secrets", %{jido: jido} do
    agent = start_agent!(jido, AgentLiveDebugger, initial_state: %{secret_token: "secret"})
    assert {:ok, _} = AgentLiveDebugger.record_result(agent, input: %{result: "done"})

    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.agent_module == AgentLiveDebugger
    assert snapshot.state == %{status: "complete", result: "done"}
    assert snapshot.state_version == 1
    refute inspect(snapshot) =~ "secret"
  end

  test "inspection reads the committed state while an Action is still running", %{jido: jido} do
    owner = self()

    barrier = fn ->
      send(owner, {:inspection_waiting, self()})

      receive do
        :release -> :ok
      after
        5_000 -> raise "inspection barrier was not released"
      end
    end

    agent = start_agent!(jido, InspectionFixture)

    task =
      Task.async(fn ->
        InspectionFixture.record_result(agent,
          input: %{result: "later"},
          context: %{inspection_barrier: barrier}
        )
      end)

    assert_receive {:inspection_waiting, worker}, 1_000
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state == %{status: "idle", result: ""}
    assert snapshot.state_version == 0
    refute snapshot.runtime_status == :idle
    send(worker, :release)
    assert {:ok, _} = Task.await(task)
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state.result == "later"
    assert snapshot.state_version == 1
  end
end
