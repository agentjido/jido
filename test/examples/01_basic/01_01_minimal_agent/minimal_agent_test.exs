defmodule JidoTest.Examples.Basic.MinimalAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.MinimalAgent

  test "direct and live execution agree on route defaults and Signal overrides", %{jido: jido} do
    definition = MinimalAgent.agent()
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
      assert {:error, %Jido.Error.ValidationError{}} =
               MinimalAgent.increment(server, 1, timeout: :invalid)

      assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
      assert {:ok, ^candidate} = MinimalAgent.increment(server, 0, context: %{})
      assert Server.snapshot(server) == %{agent: candidate, state_version: 2}
    end
  end

  test "the Action rejects an invalid amount before it can change state", %{jido: jido} do
    server = start_agent!(jido, MinimalAgent, error_policy: observe_errors())
    before = Server.snapshot(server)

    for amount <- ["3", nil, 1.5] do
      command = MinimalAgent.increment_signal!(amount)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               MinimalAgent.cmd(before.agent, command)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Server.call(server, command)

      assert Server.snapshot(server) == before
    end

    assert {:ok, recovered} = MinimalAgent.increment(server, 2)
    assert recovered.state == %{count: 2}
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "instances from one definition keep separate state and identity", %{jido: jido} do
    observer = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        {:ok, server} = Jido.start_agent(jido, MinimalAgent)
        send(observer, {:started, server})
        exit(:caller_finished)
      end)

    assert_receive {:started, first}
    assert_receive {:DOWN, ^monitor, :process, ^caller, :caller_finished}
    assert Process.alive?(first)
    assert {:ok, second} = Jido.start_agent(jido, MinimalAgent, id: unique_id())
    untouched = Server.snapshot(second)

    assert {:ok, changed} = Server.call(first, MinimalAgent.increment_signal!(7))
    assert changed.state == %{count: 7}
    assert Server.snapshot(first) == %{agent: changed, state_version: 1}
    assert Server.snapshot(second) == untouched
    refute changed.id == untouched.agent.id
    assert is_binary(changed.id) and byte_size(changed.id) > 0
    assert Jido.whereis_agent(jido, changed.id) == first
    assert Jido.whereis_agent(jido, untouched.agent.id) == second

    assert {:error, _reason} = Jido.start_agent(jido, MinimalAgent, id: changed.id)
    assert Server.snapshot(first) == %{agent: changed, state_version: 1}
    assert Jido.whereis_agent(jido, changed.id) == first

    for opts <- [nil, [:invalid], [id: ""], [id: 7]] do
      assert {:error, %Jido.Error.ValidationError{}} = Jido.start_agent(jido, MinimalAgent, opts)
      assert Server.snapshot(first) == %{agent: changed, state_version: 1}
    end
  end
end
