defmodule JidoTest.Examples.Basic.MinimalAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.MinimalAgent

  test "direct and live execution agree on route defaults and Signal overrides", %{jido: jido} do
    definition = MinimalAgent.definition()
    assert definition.id == nil
    assert definition.state == nil

    for {data, expected_count} <- [{%{}, 5}, {%{amount: 3}, 7}, {%{amount: 0}, 4}] do
      agent = MinimalAgent.new!(id: unique_id(), state: %{count: 4})
      server = start_agent!(jido, MinimalAgent, id: agent.id, initial_state: agent.state)
      before = Server.snapshot(server)
      command = signal("basic.minimal.increment", data)

      assert {:ok, candidate, []} = MinimalAgent.cmd(agent, command)
      assert candidate.state == %{count: expected_count}
      assert agent.state == %{count: 4}
      assert Server.snapshot(server) == before

      assert {:ok, ^candidate} = Server.call(server, command)
      assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
      # The domain helper uses the same Server options and result contract.
      {:ok, route_signal_1} = MinimalAgent.increment_signal(%{amount: 1})

      assert {:error, %Jido.Error.ValidationError{}} =
               Jido.AgentServer.call(server, route_signal_1, timeout: :invalid)

      assert Server.snapshot(server) == %{agent: candidate, state_version: 1}

      {:ok, route_signal_2} = MinimalAgent.increment_signal(%{amount: 0})

      assert {:ok, ^candidate} =
               Jido.AgentServer.call(server, route_signal_2, context: %{})

      assert Server.snapshot(server) == %{agent: candidate, state_version: 2}
    end
  end

  test "the Action rejects an invalid amount before it can change state", %{jido: jido} do
    server = start_agent!(jido, MinimalAgent, error_policy: observe_errors())
    before = Server.snapshot(server)

    for amount <- ["3", nil, 1.5] do
      {:ok, command} =
        MinimalAgent.increment_signal(%{amount: amount})

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               MinimalAgent.cmd(before.agent, command)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Server.call(server, command)

      assert Server.snapshot(server) == before
    end

    {:ok, route_signal_3} = MinimalAgent.increment_signal(%{amount: 2})

    assert {:ok, recovered} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert recovered.state == %{count: 2}
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "instances from one definition keep separate state and identity", %{jido: jido} do
    first = start_agent!(jido, MinimalAgent)
    second = start_agent!(jido, MinimalAgent)
    untouched = Server.snapshot(second)

    {:ok, command_signal_1} = MinimalAgent.increment_signal(%{amount: 7})

    assert {:ok, changed} =
             Server.call(
               first,
               command_signal_1
             )

    assert changed.state == %{count: 7}
    assert Server.snapshot(first) == %{agent: changed, state_version: 1}
    assert Server.snapshot(second) == untouched
    refute changed.id == untouched.agent.id
    assert is_binary(changed.id) and byte_size(changed.id) > 0
    assert Jido.whereis_agent(jido, changed.id) == first
    assert Jido.whereis_agent(jido, untouched.agent.id) == second
  end
end
