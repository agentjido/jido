Code.require_file("executable_continuation.ex", __DIR__)

defmodule Jido.Examples.Workflow.ExecutableContinuationTest do
  use Jido.Test.Agent.WorkflowSDKCase
  @moduletag :integration

  alias Jido.Examples.ExecutableContinuation, as: Example

  test "Invoke selects a Flow that shares context and commits one terminal result", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    {:ok, route_signal_1} = Example.add_repeatedly_signal(%{value: 2, remaining: 2})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_1, context: %{request: "chain"})

      assert turn_result.status in [:committed, :waiting]
      agent = Jido.AgentServer.snapshot(server).agent
    )

    assert agent.state == %{value: 4, request: "chain"}
    snapshot = Server.snapshot(server)
    assert snapshot.agent == agent
    assert snapshot.agent_revision == before.agent_revision + 1
  end

  test "the selected Flow's iteration limit prevents an intermediate commit", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_2} = Example.add_repeatedly_signal(%{value: 1, remaining: 0})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_2, [])

      assert turn_result.status in [:committed, :waiting]
    )

    before = Server.snapshot(server)

    {:ok, route_signal_3} = Example.add_repeatedly_signal(%{value: 2, remaining: 4})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert Enum.any?(
             errors(error),
             &(&1.type == :execution_error and &1.details.max_iterations == 3)
           )

    assert Server.snapshot(server) == before

    {:ok, route_signal_4} = Example.add_repeatedly_signal(%{value: 2, remaining: 3})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_4, [])

      assert turn_result.status in [:committed, :waiting]
    )

    assert Server.snapshot(server).agent_revision == 2
  end

  test "the Flow validates initial continuation input", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    {:ok, route_signal_5} = Example.add_repeatedly_signal(%{value: 2, remaining: -1})

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Jido.Error.ValidationError{details: %{phase: :flow_input}}
            }} = Jido.AgentServer.call(server, route_signal_5, [])

    assert Server.snapshot(server) == before
  end
end
