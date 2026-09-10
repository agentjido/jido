defmodule JidoTest.Examples.Workflow.ExecutableContinuationTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.ExecutableContinuation, as: Example

  test "Flow and Action continuations share context and commit one terminal result", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_continuations: 5])
    before = Server.snapshot(server)

    assert {:ok, agent} =
             Example.add_repeatedly(server, 2, 2, context: %{request: "chain"})

    assert agent.state == %{value: 4, request: "chain"}
    assert Server.snapshot(server) == %{agent: agent, state_version: before.state_version + 1}
  end

  test "one continuation budget bounds the complete chain", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_continuations: 3])
    assert {:ok, _} = Example.add_repeatedly(server, 1, 0)
    before = Server.snapshot(server)

    assert {:error, error} = Example.add_repeatedly(server, 2, 2)

    assert Enum.any?(
             errors(error),
             &(&1.type == :execution_error and
                 &1.message == "continuation limit exceeded" and
                 &1.details.max_continuations == 3 and &1.details.count == 4)
           )

    assert Server.snapshot(server) == before
    assert {:ok, _} = Example.add_repeatedly(server, 2, 1)
    assert Server.snapshot(server).state_version == 2
  end

  test "the Flow validates initial continuation input", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    assert {:error, %Jido.Flow.Error.InvalidExecutionError{details: %{phase: :flow_input}}} =
             Example.add_repeatedly(server, 2, -1)

    assert Server.snapshot(server) == before
  end
end
