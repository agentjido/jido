defmodule JidoTest.Examples.Basic.MinimalAgentTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.MinimalAgent

  test "direct and live execution agree on route defaults and Signal overrides", %{jido: jido} do
    assert %{id: nil, state: nil} = MinimalAgent.definition()

    for {data, expected_count} <- [{%{}, 5}, {%{amount: 3}, 7}, {%{amount: 0}, 4}] do
      agent = MinimalAgent.instantiate!(id: unique_id(), state: %{count: 4})
      server = start_counter(jido, id: agent.id, state: agent.state)
      before = Server.snapshot(server)
      assert {:ok, command} = MinimalAgent.increment_signal(data)

      assert {:ok, candidate, []} = MinimalAgent.cmd(agent, command)
      assert candidate.state == %{count: expected_count}
      assert agent.state == %{count: 4}
      assert Server.snapshot(server) == before

      assert {:ok, ^candidate, []} = Server.call(server, command)
      assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
    end
  end

  test "invalid amounts preserve the commit and a later valid command succeeds", %{jido: jido} do
    server = start_counter(jido)
    before = Server.snapshot(server)

    for amount <- ["3", nil, 1.5] do
      assert {:ok, command} = MinimalAgent.increment_signal(%{amount: amount})

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               MinimalAgent.cmd(before.agent, command)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Server.call(server, command)
      assert Server.snapshot(server) == before
    end

    assert {:ok, command} = MinimalAgent.increment_signal(%{amount: 2})
    assert {:ok, recovered, []} = Server.call(server, command)
    assert recovered.state == %{count: 2}
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "instances keep separate state and identity", %{jido: jido} do
    first = start_counter(jido)
    second = start_counter(jido)
    untouched = Server.snapshot(second)
    assert {:ok, command} = MinimalAgent.increment_signal(%{amount: 7})

    assert {:ok, changed, []} = Server.call(first, command)
    assert changed.state == %{count: 7}
    assert Server.snapshot(first) == %{agent: changed, state_version: 1}
    assert Server.snapshot(second) == untouched
    refute changed.id == untouched.agent.id
    assert Jido.whereis_agent(jido, changed.id) == first
    assert Jido.whereis_agent(jido, untouched.agent.id) == second
  end

  defp start_counter(jido, opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :id, &unique_id/0)
    {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, MinimalAgent, opts)
    assert :ok = Server.await_ready(server)
    server
  end
end
