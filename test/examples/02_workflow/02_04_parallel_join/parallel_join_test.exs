defmodule JidoTest.Examples.Workflow.ParallelJoinTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.ParallelJoin, as: Example

  test "the generated command applies defaults and validates Flow input", %{jido: jido} do
    assert {:ok, signal} = Example.fetch_pair_signal(3)
    assert signal.type == "workflow.parallel"
    assert signal.source == "/workflow"
    assert signal.data == %{value: 3}

    server = start_agent!(jido, Example)
    assert {:ok, agent} = Example.fetch_pair(server, 3, context: %{request: "generated"})
    assert agent.state.result.left == %{side: :left, value: 3, request: "generated"}
    assert agent.state.result.right == %{side: :right, value: 3, request: "generated"}
    before = Server.snapshot(server)

    assert {:error,
            %Jido.Flow.Error.InvalidExecutionError{
              details: %{phase: :flow_input, errors: [%{path: [:fail]}]}
            }} = Example.fetch_pair(server, 3, :invalid)

    assert Server.snapshot(server) == before
  end

  test "independent branches join their named results in one commit", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    before = Server.snapshot(server)

    assert {:ok, agent} = Example.fetch_pair(server, 2, context: %{request: "shared"})

    assert agent.state.result == %{
             left: %{side: :left, value: 2, request: "shared"},
             right: %{side: :right, value: 2, request: "shared"}
           }

    assert Server.snapshot(server) == %{agent: agent, state_version: before.state_version + 1}
  end

  test "a branch failure prevents the join and preserves committed state", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Example.fetch_pair(server, 1)
    before = Server.snapshot(server)

    assert {:error, error} = Example.fetch_pair(server, 2, :left)

    assert Enum.any?(
             errors(error),
             &(&1.message == "retriever failed" and &1.details.source == :left)
           )

    assert Server.snapshot(server) == before
  end
end
