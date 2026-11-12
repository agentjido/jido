defmodule Jido.Agent.PreparedEvaluationTest do
  use Jido.Test.Case, async: true

  alias Jido.Agent.Runner
  alias Jido.Agent
  alias Jido.AgentServer.Command
  alias Jido.Signal
  alias Jido.Test.AgentServer.Fixtures.Add

  defmodule CustomRouteAgent do
    @moduledoc false

    use Jido.Agent, name: "turn_evaluation_custom_route"

    state do
      schema Jido.Joi.object(%{
               count: Jido.Joi.integer() |> Jido.Joi.default(0),
               history: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])
             })
    end

    routes do
      route "source.*", Add, defaults: %{by: 1, label: "route"}
    end
  end

  test "route selection rejects malformed Signal types before callback", %{jido: jido} do
    agent = CustomRouteAgent.instantiate!(id: Jido.Id.uuid7())
    {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, agent)
    before = Jido.Test.AgentServer.Assertions.committed(server)
    source = Signal.new!("source.custom", %{observer: self()}, source: "/test")

    for type <- [:invalid, nil, 42] do
      assert {:error, %Jido.Error.RoutingError{}} = Agent.cmd(agent, %{source | type: type})

      assert {:error, %Jido.Error.RoutingError{}} =
               Jido.AgentServer.call(server, %{source | type: type})

      assert Jido.Test.AgentServer.Assertions.committed(server) == before
    end
  end

  test "route selection prepares one bound Flow instruction" do
    source = Signal.new!("source.route", %{observer: self()}, source: "/test")
    agent = CustomRouteAgent.instantiate!(id: "direct")

    assert {:ok, prepared} = Runner.prepare(agent, source, [])
    assert prepared.source_signal == source

    assert %Jido.Instruction{
             kind: :flow,
             target: %Jido.Flow{
               components: %{"action" => %{call: %{kind: :action, target: Add}}}
             },
             params: %{by: 1, label: "route", observer: observer},
             context: %{signal: ^source}
           } = prepared.instruction

    assert observer == self()
    assert prepared.signal.type == "source.route"
    assert prepared.instruction.context.signal == prepared.signal
  end

  test "direct and live evaluation keep the selected Turn fixed", %{jido: jido} do
    source = Signal.new!("source.route", %{observer: self()}, source: "/test")
    agent = CustomRouteAgent.instantiate!(id: "live")

    assert {:ok, direct, []} = Jido.Agent.cmd(agent, source)
    assert direct.state == %{count: 1, history: ["route"]}

    assert {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, agent)
    assert {:ok, live, _} = Jido.AgentServer.call(server, source)
    assert live.state == direct.state
  end

  test "the private evaluator reports its closed preparation and finalization stages" do
    source = Signal.new!("missing.route", %{}, source: "/test")

    agent =
      Agent.define!(%{name: "missing_route"})
      |> Agent.instantiate!(id: Jido.Id.uuid7())

    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Agent.Plugin.declarations(agent))
    {:ok, command} = Command.new(agent, source)

    assert {:error, :route, %Jido.Error.ValidationError{code: :unmatched_input}} =
             Runner.prepare_admitted(command, source, [], specs)

    command = %{command | context: %{agent_id: "reserved"}}

    assert {:error, :input, %{__exception__: true}} =
             Runner.prepare_admitted(command, source, [], specs)

    selected = Signal.new!("source.route", %{observer: self()}, source: "/test")
    selected_agent = CustomRouteAgent.instantiate!(id: "stages")

    {:ok, selected_specs} =
      Jido.Plugin.Normalizer.normalize_all(Agent.Plugin.declarations(selected_agent))

    {:ok, selected_command} = Command.new(selected_agent, selected)

    assert {:ok, prepared} =
             Runner.prepare_admitted(
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
