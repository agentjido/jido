defmodule JidoTest.Examples.Basic.TypedCommandAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError
  alias Jido.Examples.TypedCommandAgent, as: Agent

  test "route defaults and typed command input agree in direct and live execution", %{jido: jido} do
    cases = [
      {Agent.patch_profile_signal!(), %{name: "Route default", email: true, push: true}},
      {Agent.patch_profile_signal!(%{name: " New "}), %{name: "New", email: true, push: false}},
      {Agent.patch_profile_signal!(%{push: false}), %{name: "Initial", email: true, push: false}}
    ]

    for {command, expected_profile} <- cases do
      server = start_agent!(jido, Agent)
      before = Server.snapshot(server)

      assert before.agent.state == %{
               count: 0,
               minimum: 0,
               maximum: 5,
               profile: %{name: "Initial", email: true, push: false}
             }

      assert {:ok, candidate, []} = Agent.cmd(before.agent, command)
      assert candidate.state.profile == expected_profile
      assert Server.snapshot(server) == before

      assert {:ok, ^candidate} = Server.call(server, command)
      assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
    end
  end

  test "invalid typed input does not commit and a valid command recovers", %{jido: jido} do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    for patch <- [%{push: "yes"}, %{unknown: true}, nil] do
      command = Agent.patch_profile_signal!(patch)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Agent.cmd(before.agent, command)

      assert {:error, %Jido.Action.Error.InvalidInputError{}} = Server.call(server, command)
      assert Server.snapshot(server) == before
    end

    assert {:ok, recovered} = Agent.patch_profile(server, %{name: "Valid"})
    assert recovered.state.profile.name == "Valid"
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "complete Agent validation rejects an out-of-bounds candidate", %{jido: jido} do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    assert {:error, %ValidationError{message: "Agent state does not match its schema"}} =
             Agent.set_count(server, 6)

    assert Server.snapshot(server) == before

    assert {:ok, recovered} = Agent.set_count(server, 5)
    assert recovered.state.count == 5
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end
end
