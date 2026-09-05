defmodule JidoTest.Examples.Basic.TypedCommandAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Error.{RoutingError, ValidationError}
  alias Jido.Examples.DirectiveAgent.Effects
  alias Jido.Examples.TypedCommandAgent, as: Agent
  alias Jido.Examples.TypedCommandAgent.OwnedState

  test "construction preserves defaults and root constraints with and without Plugin state", %{
    jido: jido
  } do
    for plugins <- [[], [OwnedState]] do
      definition = %{Agent.agent() | plugins: plugins}
      {:ok, valid} = Jido.Agent.instantiate(definition, id: unique_id())
      server = start_agent!(jido, definition, id: valid.id)

      assert valid.state.count == 0
      assert valid.state.profile == %{name: "Initial", email: true, push: false}
      assert Map.has_key?(valid.state, :owned) == (plugins != [])
      assert Server.snapshot(server) == %{agent: valid, state_version: 0}

      for state <- [
            %{minimum: 2},
            %{count: -1},
            %{count: 6},
            %{minimum: 3, maximum: 1}
          ] do
        id = unique_id()

        assert {:error, %ValidationError{}} =
                 Jido.Agent.instantiate(definition, id: id, state: state)

        assert {:error, %ValidationError{}} =
                 Jido.start_agent(jido, definition, id: id, initial_state: state)

        assert Jido.whereis_agent(jido, id) == nil
      end
    end
  end

  test "route defaults merge shallowly before direct and live Action validation", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    for patch <- [%{push: "yes"}, %{unknown: true}, nil] do
      command = signal("basic.profile.patch", %{patch: patch})

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Agent.cmd(before.agent, command, context: %{observer: self()})

      assert {:error, %Jido.Action.Error.InvalidInputError{}} =
               Server.call(server, command, context: %{observer: self()})

      assert Server.snapshot(server) == before
      assert Effects.records(server) == []
    end

    refute_received {:sdk_action, _}

    for data <- [nil, [], "invalid"] do
      command = signal("basic.profile.patch", data)

      assert {:error, %ValidationError{message: "Agent Signal data must be a map"}} =
               Agent.cmd(before.agent, command, context: %{observer: self()})

      assert {:error, %ValidationError{message: "Agent Signal data must be a map"}} =
               Server.call(server, command, context: %{observer: self()})

      assert Server.snapshot(server) == before
    end

    refute_received {:sdk_action, _}

    cases = [
      {%{}, %{name: "Route default", email: true, push: true}},
      {%{patch: %{name: " New "}}, %{name: "New", email: true, push: false}},
      {%{patch: %{push: false}}, %{name: "Initial", email: true, push: false}}
    ]

    for {data, expected_profile} <- cases do
      server = start_agent!(jido, Agent)
      before = Server.snapshot(server)
      command = signal("basic.profile.patch", data)

      assert {:ok, candidate, []} = Agent.cmd(before.agent, command, context: %{observer: self()})
      assert_receive {:sdk_action, :patch}
      assert Server.snapshot(server) == before

      assert {:ok, ^candidate} = Server.call(server, command, context: %{observer: self()})
      assert_receive {:sdk_action, :patch}
      refute_received {:sdk_action, :set_count}

      assert candidate.state == %{before.agent.state | profile: expected_profile}
      assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
      assert Effects.records(server) == []
    end
  end

  test "an invalid candidate cannot commit or dispatch after successful Action execution", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)
    command = signal("basic.count.set", %{count: 6})

    result = Server.call(server, command, context: %{observer: self()})
    assert_receive {:sdk_action, :set_count}
    await_idle(server)
    assert {:error, %ValidationError{message: "Agent state does not match its schema"}} = result
    assert Server.snapshot(server) == before
    assert Effects.records(server) == []

    assert {:ok, recovered} =
             Server.call(server, signal("basic.count.set", %{count: 5}),
               context: %{observer: self()}
             )

    await_idle(server)
    assert recovered.state.count == 5
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
    assert [%{label: "count accepted"}] = Effects.records(server)
  end

  test "direct and live routing failures share one error contract and leave the Server usable", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)
    input = %{patch: %{name: "Wrong"}, count: 1}

    for {type, expected_details} <- [
          {"basic.unknown", %{reason: :no_handlers_found, route: "basic.unknown"}},
          {"basic.ambiguous", %{count: 2, targets: [Agent.Patch, Agent.SetCount]}}
        ] do
      command = signal(type, input)

      assert {:error, %RoutingError{} = direct_error} =
               Agent.cmd(before.agent, command, context: %{observer: self()})

      assert {:error, %RoutingError{} = live_error} =
               Server.call(server, command, context: %{observer: self()})

      assert direct_error.target == type
      assert live_error.target == type
      assert Jido.Error.to_map(live_error) == Jido.Error.to_map(direct_error)

      for {key, value} <- expected_details do
        assert direct_error.details[key] == value
        assert live_error.details[key] == value
      end

      assert Server.snapshot(server) == before
      refute_received {:sdk_action, _}
      assert Effects.records(server) == []
    end

    assert {:ok, changed} =
             Server.call(
               server,
               signal("basic.profile.patch", %{patch: %{name: "Valid"}}),
               context: %{observer: self()}
             )

    assert_receive {:sdk_action, :patch}
    assert changed.state.profile.name == "Valid"
    assert Server.snapshot(server) == %{agent: changed, state_version: 1}
  end
end
