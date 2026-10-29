defmodule Jido.Agent.Plugin.FSMTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Plugin.FSM
  alias Jido.Persistence

  defmodule Mark do
    use Jido.Action,
      name: "fsm_mark",
      schema: Zoi.object(%{label: Zoi.atom()})

    @impl true
    def run(%{label: label}, context) do
      {:ok, %{context.agent_state | log: context.agent_state.log ++ [label]}}
    end
  end

  defmodule Fail do
    use Jido.Action, name: "fsm_fail"

    @impl true
    def run(_params, _context), do: {:error, :failed}
  end

  defmodule MarkFlow do
    use Jido.Flow, name: "fsm_mark_flow"

    flow do
      step "mark", action: Mark, params: input()
      output result("mark")
    end
  end

  defmodule OtherSelector do
    use Jido.Plugin

    @impl true
    def select_route(_selection, _opts), do: :default
  end

  defmodule Guide do
    use Jido.Agent,
      name: "fsm_guide",
      plugins: [{FSM, %{definition_vsn: 1}}]

    state do
      schema Zoi.object(%{log: Zoi.list(Zoi.atom()) |> Zoi.default([])})
    end

    state_machine do
      initial :idle
      terminal(:ready)

      transition(:start,
        from: :idle,
        route: :start,
        to: :running
      )

      transition(:finish,
        from: :running,
        route: :finish,
        to: :ready
      )
    end

    routes do
      signal_source "/plugin/fsm/guide"

      route "advance", Mark, as: :start, defaults: %{label: :started}
      route "advance", Mark, as: :finish, defaults: %{label: :finished}
      route "inspect", Mark, as: :inspect, defaults: %{label: :inspected}
    end
  end

  defmodule FailingGuide do
    use Jido.Agent,
      name: "fsm_failing_guide",
      plugins: [{FSM, %{definition_vsn: 1}}]

    state do
      schema Zoi.object(%{log: Zoi.list(Zoi.atom()) |> Zoi.default([])})
    end

    state_machine do
      initial :idle
      terminal(:ready)
      transition(:fail, from: :idle, route: :fail, to: :ready)
    end

    routes do
      signal_source "/plugin/fsm/failing"
      route "fail", Fail, as: :fail
    end
  end

  defmodule FlowGuide do
    use Jido.Agent,
      name: "fsm_flow_guide",
      plugins: [{FSM, %{definition_vsn: 1}}]

    state do
      schema Zoi.object(%{log: Zoi.list(Zoi.atom()) |> Zoi.default([])})
    end

    state_machine do
      initial :idle
      terminal(:ready)
      transition(:finish, from: :idle, route: :finish, to: :ready)
    end

    routes do
      signal_source "/plugin/fsm/flow"
      route "finish", MarkFlow, as: :finish, defaults: %{label: :flow}
    end
  end

  test "the DSL lowers to one canonical Plugin representation" do
    [entry] = Guide.definition().plugins

    assert entry.provider == FSM
    assert entry.data == machine_data()

    map_definition =
      Agent.define!(%{
        name: "map_fsm_guide",
        schema: Zoi.object(%{log: Zoi.list(Zoi.atom()) |> Zoi.default([])}),
        signal_source: "/plugin/fsm/map",
        routes: Guide.definition().routes,
        plugins: [fsm_extension(Map.delete(machine_data(), :definition_vsn))]
      })

    assert [map_entry] = map_definition.plugins
    assert map_entry.data == entry.data
  end

  test "Action success advances FSM state after normal state projection" do
    agent = Guide.instantiate!(id: "guide")
    assert agent.state.fsm == %{definition_vsn: 1, current: :idle}

    signal = Jido.Signal.new!("advance", %{}, source: agent.signal_source)

    assert {:ok, running, []} = Agent.cmd(agent, signal)
    assert running.state.log == [:started]
    assert running.state.fsm == %{definition_vsn: 1, current: :running}

    assert {:ok, ready, []} = Agent.cmd(running, signal)
    assert ready.state.log == [:started, :finished]
    assert ready.state.fsm == %{definition_vsn: 1, current: :ready}

    assert {:error, error} = Agent.cmd(ready, signal)
    assert error.details.code == :invalid_fsm_transition
    assert ready.state.fsm.current == :ready
  end

  test "an unmanaged route uses normal selection and does not advance the FSM" do
    agent = Guide.instantiate!(id: "unmanaged")
    signal = Jido.Signal.new!("inspect", %{}, source: agent.signal_source)

    assert {:ok, inspected, []} = Agent.cmd(agent, signal)
    assert inspected.state.log == [:inspected]
    assert inspected.state.fsm == agent.state.fsm
  end

  test "Action failure leaves FSM state unchanged" do
    agent = FailingGuide.instantiate!(id: "failure")
    signal = Jido.Signal.new!("fail", %{}, source: agent.signal_source)

    assert {:error, _reason} = Agent.cmd(agent, signal)
    assert agent.state.fsm == %{definition_vsn: 1, current: :idle}
  end

  test "Flow success advances FSM state only after Flow completion" do
    agent = FlowGuide.instantiate!(id: "flow")
    signal = Jido.Signal.new!("finish", %{}, source: agent.signal_source)

    assert {:ok, ready, []} = Agent.cmd(agent, signal)
    assert ready.state.log == [:flow]
    assert ready.state.fsm == %{definition_vsn: 1, current: :ready}
  end

  test "FSM state restores through Agent persistence" do
    source = {Persistence.ETS, [table: __MODULE__]}
    id = "persist-#{System.unique_integer([:positive])}"
    agent = Guide.instantiate!(id: id)
    signal = Jido.Signal.new!("advance", %{}, source: agent.signal_source)
    assert {:ok, running, []} = Agent.cmd(agent, signal)

    assert :ok = Persistence.create_agent(source, agent, namespace: "fsm")

    assert :ok =
             Persistence.save_agent(source, running,
               namespace: "fsm",
               expected_revision: 0,
               revision: 1
             )

    assert {:ok, restored, 1} =
             Persistence.load_agent_with_revision(source, Guide, id, namespace: "fsm")

    assert restored.state.fsm == %{definition_vsn: 1, current: :running}
    assert :ok = Persistence.delete_agent(source, Guide, id, namespace: "fsm")
  end

  test "Agent codec preserves the canonical FSM definition" do
    definition = Guide.definition()
    registry = JidoTest.AgentRegistry.for(definition)

    assert {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)

    assert {:ok, ^definition} =
             JidoTest.AgentRegistry.decode(JSON.decode!(JSON.encode!(document)), registry)
  end

  test "Agent mutation keeps selector and route invariants" do
    agent = Guide.instantiate!(id: "mutation")

    assert {:error, remove_error} =
             Agent.mutate(agent, [
               Directive.plugin_remove(FSM, state: :discard)
             ])

    assert remove_error.code == :duplicate

    assert {:error, add_error} =
             Agent.mutate(agent, [Directive.plugin_add(OtherSelector)])

    assert add_error.message == "Only one Agent Plugin can select routes"
    assert agent.state.fsm == %{definition_vsn: 1, current: :idle}
  end

  test "invalid graphs fail during normalization" do
    for {data, code} <- [
          {%{
             initial: :idle,
             terminal: [:ready],
             transitions: [
               %{name: :same, from: :idle, route: :one, to: :middle},
               %{name: :same, from: :middle, route: :two, to: :ready}
             ]
           }, :duplicate},
          {%{
             initial: :idle,
             terminal: [:ready],
             transitions: [
               %{name: :finish, from: :idle, route: :finish, to: :ready},
               %{name: :leave, from: :ready, route: :leave, to: :other}
             ]
           }, :terminal_fsm_transition},
          {%{
             initial: :idle,
             terminal: [:ready],
             transitions: [
               %{name: :orphan, from: :orphan, route: :finish, to: :ready}
             ]
           }, :unreachable_fsm_state}
        ] do
      assert {:error, error} = FSM.normalize(data)
      assert error.code == code
    end
  end

  test "unknown and non-executable route references fail definition validation" do
    assert {:error, unknown} =
             Agent.define(%{
               name: "unknown_fsm_route",
               routes: [route("known", :known, Mark)],
               plugins: [
                 fsm_extension(%{
                   initial: :idle,
                   terminal: [:ready],
                   transitions: [
                     %{name: :finish, from: :idle, route: :missing, to: :ready}
                   ]
                 })
               ]
             })

    assert unknown.code == :unknown_fsm_route

    assert {:error, non_executable} =
             Agent.define(%{
               name: "terminal_fsm_route",
               routes: [
                 %{
                   path: "known",
                   as: :known,
                   defaults: %{},
                   handler: %{kind: :transform, target: {__MODULE__, :identity, 1}},
                   state: :unchanged,
                   reply: nil
                 }
               ],
               plugins: [
                 fsm_extension(%{
                   initial: :idle,
                   terminal: [:ready],
                   transitions: [
                     %{name: :finish, from: :idle, route: :known, to: :ready}
                   ]
                 })
               ]
             })

    assert non_executable.code == :invalid_fsm_route
  end

  def identity(value), do: value

  defp machine_data do
    %{
      definition_vsn: 1,
      initial: :idle,
      terminal: [:ready],
      transitions: [
        %{name: :start, from: :idle, route: :start, to: :running},
        %{name: :finish, from: :running, route: :finish, to: :ready}
      ]
    }
  end

  defp fsm_extension(data) do
    %{id: FSM.id(), provider: FSM, vsn: FSM.vsn(), data: data}
  end

  defp route(path, as, target) do
    %{
      path: path,
      as: as,
      defaults: %{},
      handler: %{kind: :action, target: target},
      state: :unchanged,
      reply: nil
    }
  end
end
