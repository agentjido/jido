defmodule JidoTest.Examples.Basic.RouteSelectionTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.RouteSelection, as: Router

  test "exact, wildcard, and fallback routes have equal direct and live selection", %{jido: jido} do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, Router, id: unique_id("route-selection"))

    for {suffix, expected} <- [
          {"order.create", "create"},
          {"order.cancel", "order"},
          {"profile.show", "fallback"}
        ] do
      signal = Router.signal!(suffix)

      assert {:ok, direct, []} =
               Jido.Agent.cmd(Router.instantiate!(id: unique_id("direct-route")), signal)

      assert {:ok, live, []} = Jido.AgentServer.call(server, signal)
      assert direct.state.handler == expected
      assert live.state.handler == direct.state.handler
    end
  end

  test "a wildcard before an exact route takes precedence" do
    agent = Router.instantiate!(id: unique_id("reordered-routes"))

    directive =
      Jido.Agent.Directive.routes_reorder([
        "examples.basic.route_selection.order.*",
        "examples.basic.route_selection.order.create",
        "**"
      ])

    assert {:ok, reordered, _diff} = Jido.Agent.mutate(agent, [directive])
    assert {:ok, selected, []} = Jido.Agent.cmd(reordered, Router.signal!("order.create"))
    assert selected.state.handler == "order"
  end

  test "an Agent without a fallback returns an unmatched input error" do
    agent = Router.Strict.instantiate!(id: unique_id("strict-route"))

    assert {:error, %Jido.Agent.Error{code: :unmatched_input}} =
             Jido.Agent.cmd(agent, Router.signal!("profile.show"))
  end
end
