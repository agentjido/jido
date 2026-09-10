defmodule JidoTest.Examples.Workflow.NestedFlowTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.NestedFlow, as: Example

  test "two child Flow calls keep separate results and share caller context", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    assert {:ok, agent} =
             Example.draft_and_review(server,
               input: %{text: "draft"},
               context: %{request: "shared"}
             )

    assert agent.state.result == %{text: "draft:writer:editor", request: "shared"}
    assert Server.snapshot(server) == %{agent: agent, state_version: before.state_version + 1}
  end

  test "parent and child input contracts preserve prior state", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Example.draft_and_review(server, input: %{text: "seed"})
    before = Server.snapshot(server)

    assert {:error, parent_error} =
             Example.draft_and_review(server, input: %{text: 42})

    assert Enum.any?(errors(parent_error), &(&1.type == :flow_invalid_execution))

    assert {:error, child_error} =
             Example.draft_and_review(server, input: %{text: ""})

    assert Enum.any?(errors(child_error), &(&1.type == :flow_invalid_execution))
    assert Server.snapshot(server) == before
  end

  test "nested Flow output uses a documented context default", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, agent} = Example.draft_and_review(server, input: %{text: "plain"})
    assert agent.state.result == %{text: "plain:writer:editor", request: "none"}
  end
end
