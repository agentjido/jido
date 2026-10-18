defmodule Jido.Agent.TurnEvaluationTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Runner
  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.Agent.Turn
  alias Jido.Signal
  alias JidoTest.AgentFixtures.Add

  defmodule CustomRouteAgent do
    @moduledoc false

    use Jido.Agent, name: "turn_evaluation_custom_route"

    agent do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    routes do
      route "source.*", Add, defaults: %{by: 1, label: "route"}
    end
  end

  test "route selection rejects malformed Signal types before callback", %{jido: jido} do
    agent = CustomRouteAgent.instantiate!(id: Jido.Signal.ID.generate!())
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)
    before = JidoTest.AgentServerAssertions.committed(server)
    source = Signal.new!("source.custom", %{observer: self()}, source: "/test")

    for type <- [:invalid, nil, 42] do
      assert {:error, %Jido.Error.RoutingError{}} = Agent.cmd(agent, %{source | type: type})

      assert {:error, %Jido.Error.RoutingError{}} =
               Jido.AgentServer.call(server, %{source | type: type})

      assert JidoTest.AgentServerAssertions.committed(server) == before
    end
  end

  test "source binding accepts nil and matching Signals and rejects malformed sources" do
    source = Signal.new!("source.route", %{}, source: "/test")
    unbound = Turn.new!(Add)
    assert {:ok, bound} = Turn.bind_source(unbound, source)
    assert bound.source_signal == source
    assert {:ok, ^bound} = Turn.bind_source(bound, source)

    for value <- [:invalid, "invalid", %{id: "invalid"}] do
      assert {:error, %Jido.Error.ValidationError{subject: :source_signal}} =
               Turn.bind_source(%{unbound | source_signal: value}, source)

      assert {:error, %Jido.Error.ValidationError{subject: :source_signal}} =
               Turn.validate(%{unbound | source_signal: value})
    end
  end

  test "route selection uses the source Signal" do
    source = Signal.new!("source.route", %{observer: self()}, source: "/test")
    agent = CustomRouteAgent.instantiate!(id: "direct")

    assert {:ok, prepared} = Runner.prepare(agent, source, [])
    assert prepared.turn.source_signal == source
    assert prepared.turn.executable == Add
    assert prepared.turn.input == %{by: 1, label: "route", observer: self()}
    assert prepared.signal.type == "source.route"
    assert prepared.context.signal == prepared.signal
  end

  test "direct and live evaluation keep the selected Turn fixed", %{jido: jido} do
    source = Signal.new!("source.route", %{observer: self()}, source: "/test")
    agent = CustomRouteAgent.instantiate!(id: "live")

    assert {:ok, direct, []} = Jido.Agent.cmd(agent, source)
    assert direct.state == %{count: 1, history: ["route"]}

    assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, agent)
    assert {:ok, live, _} = Jido.AgentServer.call(server, source)
    assert live.state == direct.state
  end

  test "a Turn cannot replace its received source Signal" do
    source = Signal.new!("source.route", %{}, source: "/test")
    replacement = Signal.new!("other.route", %{}, source: "/test")
    turn = Jido.Agent.Turn.new!(Add, %{}, replacement)

    assert {:error, %Jido.Error.ValidationError{subject: :source_signal}} =
             Jido.Agent.Turn.bind_source(turn, source)
  end

  test "source binding compares the complete Signal, not only its id" do
    source = Signal.new!("source.route", %{by: 1}, source: "/test")

    for replacement <- [
          %{source | data: %{by: 2}},
          %{source | type: "other.route"},
          %{source | source: "/other"}
        ] do
      turn = Turn.new!(Add, %{}, replacement)

      assert {:error,
              %Jido.Error.ValidationError{
                subject: :source_signal,
                details: %{expected_signal_id: expected_id, turn_signal_id: turn_id}
              }} = Turn.bind_source(turn, source)

      assert expected_id == source.id
      assert turn_id == source.id
    end
  end

  test "Turn validation returns an error for values that are not Turns" do
    assert {:error,
            %Jido.Error.ValidationError{
              message: "Expected a Jido.Agent.Turn value",
              subject: Jido.Agent.Turn
            }} = Jido.Agent.Turn.validate(:invalid)
  end

  test "the private evaluator reports its closed preparation and finalization stages" do
    source = Signal.new!("missing.route", %{}, source: "/test")

    agent =
      Agent.define!(%{name: "missing_route"})
      |> Agent.instantiate!(id: Jido.Signal.ID.generate!())

    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Agent.runtime_plugins(agent))
    {:ok, command} = Command.new(agent, source)

    assert {:error, :route, %Jido.Agent.Error{code: :unmatched_input}} =
             Runner.prepare_for_server(command, source, [], specs)

    command = %{command | context: %{agent_id: "reserved"}}

    assert {:error, :input, %{__exception__: true}} =
             Runner.prepare_for_server(command, source, [], specs)

    selected = Signal.new!("source.route", %{observer: self()}, source: "/test")
    selected_agent = CustomRouteAgent.instantiate!(id: "stages")

    {:ok, selected_specs} =
      Jido.Plugin.Normalizer.normalize_all(Agent.runtime_plugins(selected_agent))

    {:ok, selected_command} = Command.new(selected_agent, selected)

    assert {:ok, prepared} =
             Runner.prepare_for_server(
               selected_command,
               selected,
               [],
               selected_specs
             )

    assert {:error, :compose, %Jido.Error.ExecutionError{}} =
             Runner.finish_for_server(prepared, :invalid)

    assert {:error, :validate, %{__exception__: true}} =
             Runner.finish_for_server(prepared, {:ok, %{count: :invalid, history: []}})
  end
end
