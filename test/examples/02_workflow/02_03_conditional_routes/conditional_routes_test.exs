defmodule JidoTest.Examples.Workflow.ConditionalRoutesTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.ConditionalRoutes, as: Example
  alias JidoTest.WorkflowService, as: Service

  test "Choice runs the first matching option and does not call the fallback", %{jido: jido} do
    client = start_supervised!({Service, %{primary: {:ok, %{answer: "primary"}}}})
    server = start_agent!(jido, Example)

    {:ok, route_signal_1} = Example.fetch_signal(%{})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_1, context: %{service: {Service, client}})

    assert agent.state == %{route: :primary, result: %{answer: "primary"}}
    assert Service.calls(client) == [primary: %{}]
    assert Server.snapshot(server) == %{agent: agent, state_version: 1}
  end

  test "explicit provider policy selects fallback or rejection", %{jido: jido} do
    server = start_agent!(jido, Example)

    unavailable =
      start_supervised!(
        {Service, %{primary: {:error, :unavailable}, fallback: {:ok, %{answer: "cache"}}}}
      )

    {:ok, route_signal_2} = Example.fetch_signal(%{})

    assert {:ok, fallback} =
             Jido.AgentServer.call(server, route_signal_2,
               context: %{service: {Service, unavailable}}
             )

    assert fallback.state == %{route: :fallback, result: %{answer: "cache"}}
    assert Service.calls(unavailable) == [primary: %{}, fallback: %{}]
    before = Server.snapshot(server)

    forbidden = start_supervised!({Service, %{primary: {:error, :forbidden}}}, id: :forbidden)

    {:ok, route_signal_3} = Example.fetch_signal(%{})

    assert {:error, error} =
             Jido.AgentServer.call(server, route_signal_3,
               context: %{service: {Service, forbidden}}
             )

    assert Enum.any?(errors(error), &(&1.message == "primary rejected"))
    assert Service.calls(forbidden) == [primary: %{}]
    assert Server.snapshot(server) == before
  end
end
