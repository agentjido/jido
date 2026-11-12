Code.require_file("state_middleware.ex", __DIR__)

defmodule Jido.Examples.Plugins.StateMiddlewareTest do
  use Jido.Test.Case, async: true
  @moduletag :integration
  alias Jido.Examples.Plugins.StateMiddleware.Agent
  alias Jido.Signal

  test "state middleware reads the Turn and changes only its owned field", %{jido: jido} do
    first = input_signal(2, "first")
    direct = Agent.instantiate!(id: unique_id("state-middleware-direct"))

    assert {:ok, candidate, [_note]} = Jido.Agent.cmd(direct, first)
    assert direct.state.count == 0

    assert candidate.state == %{
             count: 2,
             audit: %{count_before: 0, count_after: 2, label: "first", turns: 1}
           }

    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: unique_id("state-middleware-live"))

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, first)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    assert committed.state == candidate.state

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, input_signal(3, "second"))

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

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
