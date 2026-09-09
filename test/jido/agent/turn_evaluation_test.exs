defmodule Jido.Agent.TurnEvaluationTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Command.Runner
  alias Jido.Agent
  alias Jido.Plugin
  alias Jido.Signal
  alias JidoTest.AgentFixtures.Add

  defmodule RewriteType do
    @moduledoc false
    use Jido.Plugin

    @impl true
    def prepare(command, _opts) do
      send(command.signal.data.observer, {:prepared, command.signal.type})
      {:ok, %{command | signal: %{command.signal | type: "changed.route"}}}
    end
  end

  defmodule CustomRouteAgent do
    @moduledoc false

    use Jido.Agent,
      name: "turn_evaluation_custom_route",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([])
        }),
      plugins: [RewriteType]

    @impl true
    def handle_signal(%Signal{} = signal, _agent) do
      send(signal.data.observer, {:selected, signal.type})
      Jido.Agent.Turn.new(Add, %{by: 1, label: signal.type})
    end
  end

  test "custom selection uses the source Signal before Plugin preparation" do
    source = Signal.new!("source.route", %{observer: self()}, source: "/test")
    agent = CustomRouteAgent.new!(id: "direct")

    assert {:ok, prepared} = Runner.prepare(agent, source, [])
    assert prepared.source_signal == source
    assert prepared.turn.source_signal == source
    assert prepared.turn.executable == Add
    assert prepared.turn.input == %{by: 1, label: "source.route"}
    assert prepared.signal.type == "changed.route"
    assert prepared.context.signal == prepared.signal

    assert_receive {:selected, "source.route"}
    assert_receive {:prepared, "source.route"}
  end

  test "direct and live evaluation keep the selected custom Turn fixed", %{jido: jido} do
    source = Signal.new!("source.route", %{observer: self()}, source: "/test")
    agent = CustomRouteAgent.new!(id: "live")

    assert {:ok, direct, []} = Jido.Agent.cmd(agent, source)
    assert direct.state == %{count: 1, history: ["source.route"]}

    assert {:ok, server} = Jido.start_agent(jido, agent)
    assert {:ok, live} = Jido.AgentServer.call(server, source)
    assert live.state == direct.state

    assert_receive {:selected, "source.route"}
    assert_receive {:prepared, "source.route"}
    assert_receive {:selected, "source.route"}
    assert_receive {:prepared, "source.route"}
  end

  test "a custom Turn cannot replace its received source Signal" do
    source = Signal.new!("source.route", %{}, source: "/test")
    replacement = Signal.new!("other.route", %{}, source: "/test")
    turn = Jido.Agent.Turn.new!(Add, %{}, replacement)

    assert {:error, %Jido.Error.ValidationError{subject: :source_signal}} =
             Jido.Agent.Turn.bind_source(turn, source)
  end

  test "the private evaluator reports its closed preparation and finalization stages" do
    source = Signal.new!("missing.route", %{}, source: "/test")
    agent = Agent.new!(name: "missing_route") |> Agent.instantiate!()
    {:ok, specs} = Plugin.normalize_all(agent.plugins)

    assert {:error, :route, %Jido.Error.RoutingError{}} =
             Runner.prepare_for_server(agent, source, source, [], specs)

    assert {:error, :input, %Jido.Error.ValidationError{}} =
             Runner.prepare_for_server(agent, source, source, [context: :invalid], specs)

    selected = Signal.new!("source.route", %{observer: self()}, source: "/test")
    selected_agent = CustomRouteAgent.new!(id: "stages")
    {:ok, selected_specs} = Plugin.normalize_all(selected_agent.plugins)

    assert {:ok, prepared} =
             Runner.prepare_for_server(
               selected_agent,
               selected,
               selected,
               [],
               selected_specs
             )

    assert {:error, :compose, %Jido.Error.ExecutionError{}} =
             Runner.finish_for_server(prepared, :invalid)

    assert {:error, :validate, %Jido.Error.ValidationError{}} =
             Runner.finish_for_server(prepared, {:ok, %{count: :invalid, history: []}})
  end
end
