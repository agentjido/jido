defmodule JidoTest.Examples.Workflow.NestedFlowTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.NestedFlow, as: Example

  test "two child Flow calls keep separate results and share caller context", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    {:ok, route_signal_1} = Example.draft_and_review_signal(%{text: "draft"})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_1, context: %{request: "shared"})

    assert agent.state.result == %{text: "draft:writer:editor", request: "shared"}
    assert Server.snapshot(server) == %{agent: agent, state_version: before.state_version + 1}
  end

  test "parent and child input contracts preserve prior state", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_2} = Example.draft_and_review_signal(%{text: "seed"})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_2, [])

    before = Server.snapshot(server)

    {:ok, route_signal_3} = Example.draft_and_review_signal(%{text: 42})

    assert {:error, parent_error} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert Enum.any?(errors(parent_error), &(&1.type == :flow_invalid_execution))

    {:ok, route_signal_4} = Example.draft_and_review_signal(%{text: ""})

    assert {:error, child_error} =
             Jido.AgentServer.call(server, route_signal_4, [])

    assert Enum.any?(errors(child_error), &(&1.type == :flow_invalid_execution))
    assert Server.snapshot(server) == before
  end

  test "nested Flow output uses a documented context default", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_5} = Example.draft_and_review_signal(%{text: "plain"})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert agent.state.result == %{text: "plain:writer:editor", request: "none"}
  end
end
