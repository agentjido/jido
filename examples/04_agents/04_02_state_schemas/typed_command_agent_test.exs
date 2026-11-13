Code.require_file("typed_command_agent.ex", __DIR__)

defmodule Jido.Examples.Basic.TypedCommandAgentTest do
  use Jido.Test.Case, async: true
  @moduletag :integration
  alias Jido.Error.ValidationError, as: Error
  alias Jido.Examples.TypedCommandAgent, as: Agent

  test "route defaults and typed command input agree in direct and live execution", %{jido: jido} do
    {:ok, command_signal_1} = Agent.patch_profile_signal(%{})
    {:ok, command_signal_2} = Agent.patch_profile_signal(%{patch: %{name: " New "}})
    {:ok, command_signal_3} = Agent.patch_profile_signal(%{patch: %{push: false}})

    cases = [
      {command_signal_1, %{name: "Route default", email: true, push: true}},
      {command_signal_2, %{name: "New", email: true, push: false}},
      {command_signal_3, %{name: "Initial", email: true, push: false}}
    ]

    for {command, expected_profile} <- cases do
      server = start_agent!(jido, Agent)
      before = Jido.AgentServer.snapshot(server)

      assert before.agent.state == %{
               count: 0,
               minimum: 0,
               maximum: 5,
               profile: %{name: "Initial", email: true, push: false}
             }

      assert {:ok, candidate, []} = Agent.cmd(before.agent, command)
      assert candidate.state.profile == expected_profile
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

  test "invalid typed input does not commit and a valid command recovers", %{jido: jido} do
    server = start_agent!(jido, Agent)
    before = Jido.AgentServer.snapshot(server)

    for patch <- [%{push: "yes"}, %{unknown: true}, nil] do
      {:ok, command} =
        Agent.patch_profile_signal(%{patch: patch})

      assert {:error, %Jido.Error.ValidationError{}} = Agent.cmd(before.agent, command)

      assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: %Jido.Error.ValidationError{}}} =
               Jido.AgentServer.call(server, command)

      assert Jido.AgentServer.snapshot(server) == before
    end

    {:ok, route_signal_1} = Agent.patch_profile_signal(%{patch: %{name: "Valid"}})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_1, [])

      assert turn_result.status in [:committed, :waiting]
      recovered = Jido.AgentServer.snapshot(server).agent
    )

    assert recovered.state.profile.name == "Valid"
    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == recovered
    assert snapshot.agent_revision == 1
  end

  test "complete Agent validation rejects an out-of-bounds candidate", %{jido: jido} do
    server = start_agent!(jido, Agent)
    before = Jido.AgentServer.snapshot(server)

    {:ok, route_signal_2} = Agent.set_count_signal(%{count: 6})

    assert {:error, %Error{code: :invalid_state, path: [:state]}} =
             Agent.cmd(before.agent, route_signal_2)

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Error{code: :invalid_state, path: [:state]}
            }} = Jido.AgentServer.call(server, route_signal_2)

    assert Jido.AgentServer.snapshot(server) == before

    {:ok, route_signal_3} = Agent.set_count_signal(%{count: 5})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_3, [])

      assert turn_result.status in [:committed, :waiting]
      recovered = Jido.AgentServer.snapshot(server).agent
    )

    assert recovered.state.count == 5
    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == recovered
    assert snapshot.agent_revision == 1
  end

  defp start_agent!(jido, agent, opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :id, &unique_id/0)
    {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, agent, opts)
    assert :ok = Jido.AgentServer.await_ready(server)
    server
  end
end
