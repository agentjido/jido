defmodule JidoTest.Examples.Workflow.ParallelJoinTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.ParallelJoin, as: Example

  test "the generated command applies defaults and validates Flow input", %{jido: jido} do
    assert {:ok, signal} = Example.fetch_pair_signal(%{value: 3})
    assert signal.type == "workflow.parallel"
    assert signal.source == "/workflow"
    assert signal.data == %{value: 3}

    server = start_agent!(jido, Example)

    {:ok, route_signal_1} = Example.fetch_pair_signal(%{value: 3})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_1, context: %{request: "generated"})

    assert agent.state.result.left == %{side: :left, value: 3, request: "generated"}
    assert agent.state.result.right == %{side: :right, value: 3, request: "generated"}
    before = Server.snapshot(server)

    {:ok, route_signal_2} = Example.fetch_pair_signal(%{value: 3, fail: :invalid})

    assert {:error,
            %Jido.Flow.Error.InvalidExecutionError{
              details: %{phase: :flow_input, errors: [%{path: [:fail]}]}
            }} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert Server.snapshot(server) == before
  end

  test "independent branches join their named results in one commit", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    before = Server.snapshot(server)

    {:ok, route_signal_3} = Example.fetch_pair_signal(%{value: 2})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_3, context: %{request: "shared"})

    assert agent.state.result == %{
             left: %{side: :left, value: 2, request: "shared"},
             right: %{side: :right, value: 2, request: "shared"}
           }

    assert Server.snapshot(server) == %{agent: agent, state_version: before.state_version + 1}
  end

  test "a branch failure prevents the join and preserves committed state", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_4} = Example.fetch_pair_signal(%{value: 1})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_4, [])

    before = Server.snapshot(server)

    {:ok, route_signal_5} = Example.fetch_pair_signal(%{value: 2, fail: :left})

    assert {:error, error} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert Enum.any?(
             errors(error),
             &(&1.message == "retriever failed" and &1.details.source == :left)
           )

    assert Server.snapshot(server) == before
  end
end
