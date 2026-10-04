defmodule JidoTest.Examples.Basic.RouteSelectionTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.RouteSelection, as: Router

  test "exact, wildcard, and fallback routes have equal direct and live selection", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Router, id: unique_id("route-selection"))

    for {suffix, expected} <- [
          {"order.create", "create"},
          {"order.priority", "high-priority"},
          {"order.cancel", "order"},
          {"profile.show", "fallback"}
        ] do
      signal = Router.signal!(suffix)

      assert {:ok, direct, []} = Jido.Agent.cmd(Router.new!(), signal)
      assert {:ok, live} = Jido.AgentServer.call(server, signal)
      assert direct.state.handler == expected
      assert live.state.handler == direct.state.handler
    end
  end

  test "an Agent without a fallback returns a routing error" do
    assert {:error, %Jido.Error.RoutingError{}} =
             Jido.Agent.cmd(Router.Strict.new!(), Router.signal!("profile.show"))
  end
end
