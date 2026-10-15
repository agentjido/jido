defmodule JidoTest.Examples.Workflow.ExecutableContinuationTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.ExecutableContinuation, as: Example

  test "Dispatch selects a Flow that shares context and commits one terminal result", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    {:ok, route_signal_1} = Example.add_repeatedly_signal(%{value: 2, remaining: 2})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_1, context: %{request: "chain"})

    assert agent.state == %{value: 4, request: "chain"}
    assert Server.snapshot(server) == %{agent: agent, state_version: before.state_version + 1}
  end

  test "the selected Flow's iteration limit prevents an intermediate commit", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_2} = Example.add_repeatedly_signal(%{value: 1, remaining: 0})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_2, [])

    before = Server.snapshot(server)

    {:ok, route_signal_3} = Example.add_repeatedly_signal(%{value: 2, remaining: 4})

    assert {:error, error} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert Enum.any?(
             errors(error),
             &(&1.type == :flow_execution_error and &1.details.max_iterations == 3)
           )

    assert Server.snapshot(server) == before

    {:ok, route_signal_4} = Example.add_repeatedly_signal(%{value: 2, remaining: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_4, [])

    assert Server.snapshot(server).state_version == 2
  end

  test "the Flow validates initial continuation input", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    {:ok, route_signal_5} = Example.add_repeatedly_signal(%{value: 2, remaining: -1})

    assert {:error, %Jido.Action.Error.InvalidInputError{details: %{phase: :flow_input}}} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert Server.snapshot(server) == before
  end
end
