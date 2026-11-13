Code.require_file("minimal_agent.ex", __DIR__)

defmodule Jido.Examples.Basic.MinimalAgentTest do
  use Jido.Test.Case, async: true
  @moduletag :integration
  alias Jido.Examples.MinimalAgent

  test "direct and live execution agree on route defaults and Signal overrides", %{jido: jido} do
    assert %{id: nil, state: nil} = MinimalAgent.definition()

    for {data, expected_count} <- [{%{}, 5}, {%{amount: 3}, 7}, {%{amount: 0}, 4}] do
      agent = MinimalAgent.instantiate!(id: unique_id(), state: %{count: 4})
      server = start_counter(jido, id: agent.id, state: agent.state)
      before = Jido.AgentServer.snapshot(server)
      assert {:ok, command} = MinimalAgent.increment_signal(data)

      assert {:ok, candidate, []} = MinimalAgent.cmd(agent, command)
      assert candidate.state == %{count: expected_count}
      assert agent.state == %{count: 4}
      assert Jido.AgentServer.snapshot(server) == before

      (
        assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
                 Jido.AgentServer.call(server, command)

        assert turn_result.status in [:committed, :waiting]
        assert candidate == Jido.AgentServer.snapshot(server).agent
      )

      snapshot = Jido.AgentServer.snapshot(server)
      assert snapshot.agent == candidate
      assert snapshot.agent_revision == 1
    end
  end

  test "invalid amounts preserve the commit and a later valid command succeeds", %{jido: jido} do
    server = start_counter(jido)
    before = Jido.AgentServer.snapshot(server)

    for amount <- ["3", nil, 1.5] do
      assert {:ok, command} = MinimalAgent.increment_signal(%{amount: amount})

      assert {:error, %Jido.Error.ValidationError{}} = MinimalAgent.cmd(before.agent, command)

      assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: %Jido.Error.ValidationError{}}} =
               Jido.AgentServer.call(server, command)

      assert Jido.AgentServer.snapshot(server) == before
    end

    assert {:ok, command} = MinimalAgent.increment_signal(%{amount: 2})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, command)

      assert turn_result.status in [:committed, :waiting]
      recovered = Jido.AgentServer.snapshot(server).agent
    )

    assert recovered.state == %{count: 2}
    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == recovered
    assert snapshot.agent_revision == 1
  end

  test "instances keep separate state and identity", %{jido: jido} do
    first = start_counter(jido)
    second = start_counter(jido)
    untouched = Jido.AgentServer.snapshot(second)
    assert {:ok, command} = MinimalAgent.increment_signal(%{amount: 7})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(first, command)

      assert turn_result.status in [:committed, :waiting]
      changed = Jido.AgentServer.snapshot(first).agent
    )

    assert changed.state == %{count: 7}
    snapshot = Jido.AgentServer.snapshot(first)
    assert snapshot.agent == changed
    assert snapshot.agent_revision == 1
    assert Jido.AgentServer.snapshot(second) == untouched
    refute changed.id == untouched.agent.id
    assert Jido.whereis_agent(jido, changed.id) == first
    assert Jido.whereis_agent(jido, untouched.agent.id) == second
  end

  defp start_counter(jido, opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :id, &unique_id/0)
    {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, MinimalAgent, opts)
    assert :ok = Jido.AgentServer.await_ready(server)
    server
  end
end
