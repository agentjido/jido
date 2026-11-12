Code.require_file("route_selection.ex", __DIR__)

defmodule Jido.Examples.Basic.RouteSelectionTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Examples.RouteSelection, as: Router

  test "exact, wildcard, and fallback routes have equal direct and live selection", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Router, id: unique_id("route-selection"))

    for {suffix, expected} <- [
          {"order.create", "create"},
          {"order.cancel", "order"},
          {"profile.show", "fallback"}
        ] do
      signal = Router.signal!(suffix)

      assert {:ok, direct, []} =
               Jido.Agent.cmd(Router.instantiate!(id: unique_id("direct-route")), signal)

      assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
               Jido.AgentServer.call(server, signal)

      live = Jido.AgentServer.snapshot(server).agent
      assert direct.state.handler == expected
      assert live.state.handler == direct.state.handler
    end
  end

  test "route order is part of the fixed definition" do
    assert Enum.map(Router.definition().routes, & &1.path) == [
             "examples.basic.route_selection.order.create",
             "examples.basic.route_selection.order.*",
             "**"
           ]

    agent = Router.instantiate!(id: unique_id("declared-routes"))
    assert {:ok, selected, []} = Jido.Agent.cmd(agent, Router.signal!("order.create"))
    assert selected.state.handler == "create"
  end

  test "an Agent without a fallback returns an unmatched input error" do
    agent = Router.Strict.instantiate!(id: unique_id("strict-route"))

    assert {:error, %Jido.Error.ValidationError{code: :unmatched_input}} =
             Jido.Agent.cmd(agent, Router.signal!("profile.show"))
  end
end
