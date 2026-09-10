defmodule JidoTest.Examples.Plugins.StateMiddlewareTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Plugins.StateMiddleware.Agent
  alias Jido.Signal

  test "state middleware reads the Turn and changes only its owned field", %{jido: jido} do
    first = input_signal(2, "first")
    direct = Agent.new!(id: unique_id("state-middleware-direct"))

    assert {:ok, candidate, [_note]} = Jido.Agent.cmd(direct, first)
    assert direct.state.count == 0

    assert candidate.state == %{
             count: 2,
             audit: %{count_before: 0, count_after: 2, label: "first", turns: 1}
           }

    {:ok, server} =
      Jido.start_agent(jido, Agent, id: unique_id("state-middleware-live"))

    assert {:ok, committed} = Server.call(server, first)
    assert committed.state == candidate.state

    assert {:ok, committed} = Server.call(server, input_signal(3, "second"))

    assert committed.state == %{
             count: 5,
             audit: %{count_before: 2, count_after: 5, label: "second", turns: 2}
           }
  end

  defp input_signal(amount, label) do
    Signal.new!(
      "examples.plugins.state_middleware.add",
      %{amount: amount, label: label},
      source: "/state-middleware/test"
    )
  end
end
