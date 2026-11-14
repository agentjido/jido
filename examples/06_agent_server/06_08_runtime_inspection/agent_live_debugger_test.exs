Code.require_file("agent_live_debugger.ex", __DIR__)

defmodule Jido.Test.Examples.Runtime.InspectionFixture do
  @moduledoc false

  use Jido.Agent, name: "test_runtime_inspection", plugins: [Jido.Plugin.Timer]

  state do
    schema Jido.Joi.object(%{
             status: Jido.Joi.string() |> Jido.Joi.default("idle"),
             secret_token: Jido.Joi.string() |> Jido.Joi.default("hidden"),
             result: Jido.Joi.string() |> Jido.Joi.default("")
           })
  end

  routes do
    signal_source "/test/runtime_inspection"

    route "test.runtime.inspect", as: :record_result do
      action %{result: result},
        schema: Jido.Joi.object(%{result: Jido.Joi.string()}),
        context: context do
        Jido.Test.AgentServer.RuntimeBarrier.wait()
        {:ok, %{context.agent_state | status: "complete", result: result}}
      end
    end
  end
end

defmodule Jido.Examples.Runtime.AgentLiveDebuggerTest do
  use Jido.Test.Agent.FeatureSDKCase
  @moduletag :integration

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.Examples.AgentLiveDebugger
  alias Jido.Test.Examples.Runtime.InspectionFixture
  alias Jido.Test.AgentServer.RuntimeBarrier

  setup do
    start_supervised!(RuntimeBarrier)
    :ok = RuntimeBarrier.arm(self())
    :ok
  end

  test "a snapshot uses public inspection and removes secrets", %{jido: jido} do
    agent = start_agent!(jido, AgentLiveDebugger, state: %{secret_token: "secret"})

    {:ok, route_signal_1} = AgentLiveDebugger.record_result_signal(%{result: "done"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent, route_signal_1, [])

      assert turn_result.status in [:committed, :waiting]
    )

    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.agent_module == AgentLiveDebugger
    assert snapshot.state == %{status: "complete", result: "done"}
    assert snapshot.agent_revision == 1
    assert snapshot.work_state == :idle
    assert snapshot.active_turn_id == nil
    assert snapshot.effects == :none
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
    assert snapshot.agent_revision == 0
    assert snapshot.work_state == :running
    assert is_binary(snapshot.active_turn_id)
    assert :ok = RuntimeBarrier.release()
    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = Task.await(task)
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state.result == "later"
    assert snapshot.agent_revision == 1
  end

  test "the public status is process-neutral and the application view is redacted", %{jido: jido} do
    agent = start_agent!(jido, AgentLiveDebugger, state: %{secret_token: "debug-secret"})

    for result <- ["one", "two"] do
      {:ok, signal} = AgentLiveDebugger.record_result_signal(%{result: result})

      (
        assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
                 Jido.AgentServer.call(agent, signal)

        assert turn_result.status in [:committed, :waiting]
        _agent = Jido.AgentServer.snapshot(agent).agent
      )
    end

    status = Server.status(agent)
    assert Jido.AgentServer.Status.process_neutral?(status)
    refute inspect(AgentLiveDebugger.snapshot(agent)) =~ "debug-secret"
  end
end
