defmodule Jido.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.Agent.Turn
  alias Jido.Signal

  alias JidoTest.AgentFixtures.{
    Add,
    BlockingAdd,
    CounterAgent,
    Fail,
    InvalidBehavior,
    InvalidState,
    ObserveExecutionBoundary
  }

  defmodule TwoStepFlow do
    use Jido.Flow, name: "agent_test_two_step"

    flow do
      step "first",
        action: JidoTest.AgentFixtures.Add,
        params: %{by: input(:first_by), label: input(:first_label)}

      step "second",
        action: JidoTest.AgentFixtures.Add,
        params: %{state: result("first"), by: input(:second_by), label: input(:second_label)}

      output result("second")
    end
  end

  defmodule AuthoredAgent do
    @moduledoc false

    use Jido.Agent,
      name: "authored_agent",
      description: "Exercises the generated Agent API",
      metadata: %{category: "test", tags: ["agent", "immutable"], vsn: "1.0.0"}

    state do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    routes do
      route "counter.add", JidoTest.AgentFixtures.Add
    end
  end

  defmodule CustomRoutingAgent do
    @moduledoc false

    use Jido.Agent, name: "custom_routing_agent"

    state do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    def handle_signal(%Jido.Signal{type: "custom.add", data: data}, _agent) do
      Jido.Agent.Turn.new(JidoTest.AgentFixtures.Add, Map.put(data, :label, "custom"))
    end

    def handle_signal(
          %Jido.Signal{type: "custom.routing_failure", data: %{error: error}},
          _agent
        ),
        do: {:error, error}

    def handle_signal(_signal, _agent), do: {:error, :unsupported_signal}
  end

  defmodule InvalidCallbackAgent do
    @moduledoc false

    use Jido.Agent, name: "invalid_callback_agent"

    def handle_signal(_signal, _agent), do: :invalid_callback_result
  end

  defmodule BehaviorOnlyAgent do
    @moduledoc false

    @behaviour Jido.Agent
  end

  defmodule WithStopDirective do
    @moduledoc false

    use Jido.Action, name: "agent_with_stop_directive"

    @impl Jido.Action
    def run(%{label: label}, context) do
      state = %{context.agent_state | history: context.agent_state.history ++ [label]}
      {:ok, state, [%Jido.AgentServer.Directive.ServerStop{reason: :normal}]}
    end
  end

  defmodule CallbackPersistenceAgent do
    @moduledoc false

    use Jido.Agent, name: "callback_persistence_agent"

    state do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    @impl Jido.Agent
    def checkpoint(agent, context) do
      {:ok, %{id: agent.id, state: agent.state, saved_by: context.saved_by}}
    end

    @impl Jido.Agent
    def restore(checkpoint, context) do
      state = Map.update!(checkpoint.state, :history, &(&1 ++ [context.restored_by]))
      instantiate(id: checkpoint.id, state: state)
    end
  end

  defp build(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: build(Map.new(attrs)), else: Agent.define(attrs)
  end

  defp build(%Agent{} = value), do: Agent.define(value)

  defp build(attrs) when is_map(attrs) do
    routes = Map.get(attrs, :routes, [])

    with {:ok, routes} <-
           Agent.Data.list(routes, fn {path, target} ->
             {target, defaults} =
               case target do
                 {target, defaults} when is_map(defaults) -> {target, defaults}
                 target -> {target, %{}}
               end

             with {:ok, handler} <- Agent.Route.executable(target),
                  do: {:ok, %{path: path, handler: handler, defaults: defaults}}
           end),
         do: Agent.define(attrs |> Map.put(:routes, routes) |> Map.put_new(:module, Agent))
  end

  defp build(value), do: Agent.define(value)
  defp build!(attrs), do: attrs |> build() |> Agent.Error.unwrap!()

  defp instance!(source, opts \\ []),
    do: Agent.instantiate!(source, Keyword.put_new(opts, :id, Jido.Signal.ID.generate!()))

  defp schema do
    Zoi.object(%{
      count: Zoi.integer() |> Zoi.default(0),
      history: Zoi.list(Zoi.string()) |> Zoi.default([])
    })
  end

  defp agent_with_route(path, target) do
    build!(name: "counter", schema: schema(), routes: [{path, target}])
    |> instance!()
  end

  test "builds one neutral canonical Agent definition" do
    definition =
      build!(
        name: "counter",
        description: "Counts Signals",
        schema: schema(),
        routes: [{"counter.add", Add}]
      )

    assert %Agent{
             id: nil,
             module: Agent,
             name: "counter",
             description: "Counts Signals",
             schema: agent_schema,
             initial_state: %{},
             extensions: [],
             state: nil
           } = definition

    assert agent_schema == schema()
    assert [%{path: "counter.add", handler: %{kind: :action, target: Add}}] = definition.routes
    assert Agent.definition?(definition)
    refute Agent.instance?(definition)
    assert {:error, _} = Agent.validate(%{definition | name: nil})

    assert definition
           |> Map.from_struct()
           |> Map.keys()
           |> Enum.sort() ==
             Enum.sort([
               :id,
               :module,
               :vsn,
               :name,
               :description,
               :schema,
               :initial_state,
               :extensions,
               :signal_source,
               :state,
               :topology,
               :routes,
               :metadata
             ])
  end

  test "instantiates one definition with identity and schema defaults" do
    definition = build!(name: "counter", schema: schema())

    agent = instance!(definition, id: "counter-1")

    assert agent.id == "counter-1"
    assert agent.state == %{count: 0, history: []}
    assert agent.module == Agent
    assert Agent.instance?(agent)
    refute Agent.definition?(agent)
    assert {:error, _} = Agent.validate(%{agent | state: %{count: "invalid"}})
    assert Agent.definition(agent) == definition
    assert definition.id == nil
    assert definition.state == nil
  end

  test "keeps definitions out of instance-only operations" do
    definition =
      build!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])

    signal = Signal.new!("counter.add", %{by: 1}, source: "/test")

    assert {:error, %{__exception__: true}} = Agent.transition(definition, %{})
    assert {:error, %{__exception__: true}} = Agent.set(definition, %{})

    assert {:error, %{__exception__: true}} =
             Jido.Persistence.AgentCheckpoint.checkpoint(definition)

    assert {:error, %{__exception__: true}} = Agent.cmd(definition, signal)

    instance = instance!(definition)

    assert {:error, %{__exception__: true}} =
             Agent.instantiate(instance, id: Jido.Signal.ID.generate!())
  end

  test "rejects instance data at the definition boundary and half-instances" do
    definition = build!(name: "counter", schema: schema())

    assert {:error, %{__exception__: true}} =
             build(name: "counter", id: "counter-1")

    assert {:error, %{__exception__: true}} =
             build(name: "counter", state: %{count: 0, history: []})

    assert {:error, %{__exception__: true}} =
             Agent.validate(%{definition | id: "counter-1"})

    assert {:error, %{__exception__: true}} =
             Agent.validate(%{definition | state: %{count: 0, history: []}})
  end

  test "exposes the shared Zoi Agent schema and the Turn schema" do
    assert function_exported?(Agent, :schema, 1)
    refute function_exported?(Agent, :to_map, 1)
    refute function_exported?(Agent, :new, 2)
    refute function_exported?(Agent, :new!, 2)
    assert %Zoi.Types.Struct{module: Turn} = Turn.schema()
  end

  test "builds instances from a module that uses Jido.Agent" do
    definition = CounterAgent.definition()

    agent =
      CounterAgent.instantiate!(id: "runtime-fixture", state: %{count: 4, history: ["existing"]})

    assert %Agent{id: nil, state: nil, module: CounterAgent} = definition

    assert %Agent{
             module: CounterAgent,
             name: "counter_agent",
             description: "A module-authored Agent",
             state: %{count: 4, history: ["existing"]}
           } = agent

    assert CounterAgent.definition().name == "counter_agent"
    assert CounterAgent.definition().description == "A module-authored Agent"
    assert CounterAgent.definition().schema == agent.schema

    assert [%{path: "counter.add", handler: %{kind: :action, target: Add}}] =
             CounterAgent.definition().routes

    assert CounterAgent.definition().extensions == []
    assert Agent.definition(agent) == definition

    assert {:ok, %Agent{module: CounterAgent}} =
             Agent.instantiate(CounterAgent, id: "runtime-fixture")

    refute function_exported?(CounterAgent, :agent, 0)
    refute function_exported?(CounterAgent, :route_action, 1)
    refute function_exported?(CounterAgent, :handle_signal, 2)
    refute function_exported?(CounterAgent, :checkpoint, 2)
    refute function_exported?(CounterAgent, :restore, 2)

    assert {:error, %{__exception__: true}} =
             CounterAgent.instantiate(id: Jido.Signal.ID.generate!(), name: "changed")
  end

  test "rejects an invalid behavior, schema, route, and initial state" do
    assert {:ok, %{module: InvalidBehavior}} =
             build(name: "counter", module: InvalidBehavior)

    assert {:error, %{__exception__: true}} =
             build(name: "counter", schema: Zoi.string())

    assert {:error, %{__exception__: true}} =
             build(name: "counter", routes: [{"counter.add", String}])

    assert {:error, %{__exception__: true}} =
             build(name: "counter", schema: schema(), id: "bad", state: %{count: "bad"})

    definition = build!(name: "counter", schema: schema())

    assert {:error, %{__exception__: true}} =
             Agent.instantiate(definition, id: "runtime-fixture", state: %{count: "bad"})
  end

  test "plans one executable from one Signal without exposing Server state" do
    agent =
      build!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])
      |> instance!()

    signal = Signal.new!(type: "counter.add", source: "/test", data: %{by: 2, label: "one"})

    assert {:ok,
            %Jido.Agent.Runner.Prepared{
              turn: %Turn{
                executable: Add,
                input: %{by: 2, label: "one"}
              }
            }} = Jido.Agent.Runner.prepare(agent, signal, [])
  end

  test "selects the first executable when one Signal resolves to several" do
    agent =
      build!(
        name: "counter",
        schema: schema(),
        routes: [{"counter.*", Add}, {"counter.add", Add}]
      )
      |> instance!()

    signal = Signal.new!(type: "counter.add", source: "/test", data: %{})

    assert {:ok,
            %Jido.Agent.Runner.Prepared{
              turn: %Turn{executable: Add, source_signal: ^signal}
            }} = Jido.Agent.Runner.prepare(agent, signal, [])
  end

  test "replaces and validates the complete Agent state" do
    agent = build!(name: "counter", schema: schema()) |> instance!()

    assert {:ok, next} = Agent.transition(agent, %{count: 3, history: ["done"]})
    assert next.state == %{count: 3, history: ["done"]}
    assert next.id == agent.id
    assert next.schema == agent.schema

    assert {:error, %{__exception__: true}} =
             Agent.transition(agent, %{count: :invalid, history: []})
  end

  test "merges an explicit data mutation through the Agent schema" do
    agent = build!(name: "counter", schema: schema()) |> instance!()

    assert {:ok, next} = Agent.set(agent, count: 4)
    assert next.state == %{count: 4, history: []}
    assert agent.state == %{count: 0, history: []}

    assert {:error, %{__exception__: true}} = Agent.set(agent, count: :invalid)
  end

  test "applies the same executable turn to an Agent value without a process" do
    agent =
      build!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])
      |> instance!()

    signal = Signal.new!("counter.add", %{by: 2, label: "offline"}, source: "/test")

    assert {:ok, next, []} = Agent.cmd(agent, signal, timeout: 1_000)
    assert next.state == %{count: 2, history: ["offline"]}
    assert agent.state == %{count: 0, history: []}
  end

  test "an Agent module exposes the same cmd API" do
    agent = CounterAgent.instantiate!(id: "runtime-fixture")
    signal = Signal.new!("counter.add", %{by: 3, label: "module"}, source: "/test")

    assert {:ok, next, []} = CounterAgent.cmd(agent, signal)
    assert next.state == %{count: 3, history: ["module"]}
  end

  test "rejects invalid offline caller context with a validation error" do
    agent =
      build!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])
      |> instance!()

    signal = Signal.new!("counter.add", %{by: 1, label: "invalid"}, source: "/test")

    assert {:error, %{__exception__: true}} =
             Agent.cmd(agent, signal, context: "not a context")
  end

  test "separates portable definition data from instance data" do
    first = CounterAgent.instantiate!(id: "first", state: %{count: 1})
    second = CounterAgent.instantiate!(id: "second", state: %{count: 8})

    assert Agent.definition(first) == Agent.definition(second)
    assert %Agent{id: nil, state: nil} = Agent.definition(first)
  end

  test "checkpoints and restores complete Agent state" do
    agent = CounterAgent.instantiate!(id: "saved", state: %{count: 7, history: ["saved"]})

    assert {:ok, checkpoint} = Jido.Persistence.AgentCheckpoint.checkpoint(agent)
    assert checkpoint.format == 1
    assert checkpoint.state_format == :default
    assert checkpoint.agent === agent

    assert {:ok, restored} = Jido.Persistence.AgentCheckpoint.restore(CounterAgent, checkpoint)
    assert restored == agent
  end

  describe "module authoring API" do
    test "exposes canonical definition data and one state schema accessor" do
      definition = AuthoredAgent.definition()

      assert definition.name == "authored_agent"
      assert definition.description == "Exercises the generated Agent API"
      assert Agent.schema(definition) == definition.schema
      assert AuthoredAgent.schema() == definition.schema

      assert definition.metadata == %{
               category: "test",
               tags: ["agent", "immutable"],
               vsn: "1.0.0"
             }
    end

    test "rejects dynamic Agent state schemas" do
      anonymous_schema =
        Zoi.object(%{value: Zoi.string() |> Zoi.refine(fn _value -> :ok end)})

      lazy_schema = Zoi.object(%{value: Zoi.lazy(fn -> Zoi.string() end)})

      assert {:error, %Agent.Error{}} =
               build(name: "anonymous_schema_agent", schema: anonymous_schema)

      assert {:error, %Agent.Error{}} =
               build(name: "lazy_schema_agent", schema: lazy_schema)
    end
  end

  describe "definition construction" do
    test "accepts maps, keyword lists, and an existing definition" do
      attrs = %{name: "direct_agent", description: "Direct definition", metadata: %{tier: 1}}

      assert {:ok, from_map} = build(attrs)
      assert {:ok, from_keyword} = build(Map.to_list(attrs))
      assert {:ok, validated} = build(from_map)

      assert from_map == from_keyword
      assert validated == from_map
    end

    test "rejects unknown definition keys and invalid definition data" do
      assert {:error, %Agent.Error{code: :unknown_fields}} =
               build(name: "bad_agent", unknown: true)

      assert {:error, %{__exception__: true}} =
               build(name: "bad_agent", description: 123)

      assert {:error, %{__exception__: true}} =
               build(name: "bad_agent", metadata: Date.utc_today())

      assert {:error, %{__exception__: true}} = build([:not_a_keyword_list])
      assert {:error, %{__exception__: true}} = build(:not_definition_data)
    end

    test "raising constructors raise the returned validation error" do
      assert_raise Jido.Agent.Error, fn ->
        build!(name: "invalid_agent", schema: Zoi.string())
      end

      definition = build!(name: "valid_agent")

      assert_raise Jido.Agent.Error, fn ->
        instance!(definition, id: "")
      end
    end

    test "does not expose a general Agent map encoder" do
      agent = AuthoredAgent.instantiate!(id: "mapped", state: %{count: 2})

      refute function_exported?(Agent, :to_map, 1)
      assert agent.id == "mapped"
      assert [%{path: "counter.add", handler: %{kind: :action, target: Add}}] = agent.routes
    end
  end

  describe "instance lifecycle" do
    test "requires explicit identity at the authoring boundary" do
      definition = build!(name: "identity_agent")
      assert {:error, %Agent.Error{path: [:id]}} = Agent.instantiate(definition)
      assert {:error, %Agent.Error{path: [:id]}} = Agent.instantiate(definition, id: nil)
      assert instance!(definition, id: "agent-123").id == "agent-123"
    end

    test "merges partial initial state over schema defaults" do
      definition = build!(name: "counter", schema: schema())

      assert {:ok, agent} =
               Agent.instantiate(definition, id: "runtime-fixture", state: %{count: 9})

      assert agent.state == %{count: 9, history: []}
    end

    test "accepts only identity and state instance overrides" do
      definition = build!(name: "counter", schema: schema())

      assert {:error, %Agent.Error{code: :unknown_fields}} =
               Agent.instantiate(definition, id: Jido.Signal.ID.generate!(), name: "replacement")

      assert {:error, %{__exception__: true}} =
               Agent.instantiate(definition, [:not_a_keyword_list])
    end

    test "validates definitions and instances through explicit boundaries" do
      definition = build!(name: "counter", schema: schema())
      agent = instance!(definition, id: "counter-1")

      assert {:ok, ^definition} = Agent.validate(definition)
      assert {:ok, ^definition} = Jido.Agent.Validation.validate_definition(definition)
      assert {:ok, ^agent} = Agent.validate(agent)
      assert {:ok, ^agent} = Jido.Agent.Validation.validate_instance(agent)

      assert {:error, %{__exception__: true}} = Jido.Agent.Validation.validate_definition(agent)

      assert {:error, %{__exception__: true}} =
               Jido.Agent.Validation.validate_instance(definition)

      assert {:error, %{__exception__: true}} = Agent.validate(:not_an_agent)

      assert {:error, %{__exception__: true}} =
               Agent.validate(%{agent | state: %{count: "invalid", history: []}})
    end

    test "rejects unknown state keys at construction and transition boundaries" do
      definition = build!(name: "counter", schema: schema())

      assert {:error, %{__exception__: true}} =
               Agent.instantiate(definition, id: "runtime-fixture", state: %{extra: true})

      agent = instance!(definition)

      assert {:error, %{__exception__: true}} =
               Agent.transition(agent, %{count: 0, history: [], extra: true})
    end

    test "set replaces supplied fields and keeps other state and the source Agent" do
      nested_schema =
        Zoi.object(%{
          config: Zoi.map() |> Zoi.default(%{a: 1, b: 2}),
          count: Zoi.integer() |> Zoi.default(7)
        })

      agent =
        build!(name: "nested_agent", schema: nested_schema)
        |> instance!()

      assert {:ok, updated} = Agent.set(agent, config: %{b: 3, c: 4})
      assert updated.state == %{config: %{b: 3, c: 4}, count: 7}
      assert agent.state == %{config: %{a: 1, b: 2}, count: 7}

      config = Map.merge(agent.state.config, %{b: 3, c: 4})
      assert {:ok, merged} = Agent.set(agent, %{config: config})
      assert merged.state == %{config: %{a: 1, b: 3, c: 4}, count: 7}
    end

    test "returns a validation error for malformed set attributes" do
      agent = build!(name: "counter", schema: schema()) |> instance!()

      assert {:error, %{__exception__: true}} = Agent.set(agent, [:not_a_keyword_list])
    end
  end

  describe "Signal and command lifecycle" do
    test "the default handler uses explicit wildcards and route defaults" do
      agent = agent_with_route("counter.add", Add)
      signal = Signal.new!("counter.add", %{by: 1, label: "one"}, source: "/test")
      [route] = agent.routes

      for path <- ["counter.add", "counter.*", "counter.**", "**"] do
        routed = %{agent | routes: [%{route | path: path, defaults: %{by: 9}}]}

        assert {:ok,
                %Jido.Agent.Runner.Prepared{
                  turn: %Turn{executable: Add, input: input}
                }} = Jido.Agent.Runner.prepare(routed, signal, [])

        assert input === signal.data
      end
    end

    test "uses route input as defaults and gives Signal data precedence" do
      agent = agent_with_route("counter.static", {Add, %{by: 4, label: "default"}})

      for {data, expected} <- [
            {%{}, %{count: 4, history: ["default"]}},
            {%{by: 99}, %{count: 99, history: ["default"]}},
            {%{by: 99, label: "signal"}, %{count: 99, history: ["signal"]}}
          ] do
        signal = Signal.new!("counter.static", data, source: "/test")
        assert {:ok, updated, []} = Agent.cmd(agent, signal)
        assert updated.state == expected
      end
    end

    test "missing routes and invalid types fail without an implicit fallback" do
      agent = agent_with_route("counter.add", Add)

      for type <- ["counter.unknown", nil, :invalid] do
        signal = %{Signal.new!("counter.add", %{}, source: "/test") | type: type}
        assert {:error, _} = Jido.Agent.Runner.prepare(agent, signal, [])
        assert {:error, _} = Agent.cmd(agent, signal)
      end
    end

    test "module callbacks cannot override declared routes or inject routing failures" do
      for module <- [CustomRoutingAgent, InvalidCallbackAgent] do
        agent = module.instantiate!(id: "runtime-fixture")
        signal = Signal.new!("custom.add", %{by: 3}, source: "/test")
        assert {:error, %Jido.Agent.Error{code: :unmatched_input}} = Agent.cmd(agent, signal)
      end
    end

    test "keeps the original Signal in context when route defaults supply input" do
      agent =
        agent_with_route(
          "counter.observe",
          {ObserveExecutionBoundary, %{input: "default", settings: %{first: 1, second: 2}}}
        )

      signal =
        Signal.new!("counter.observe", %{test_pid: self(), settings: %{second: 3}},
          source: "/test"
        )

      assert {:ok, ^agent, []} = Agent.cmd(agent, signal, context: [request_id: "request-1"])

      assert_receive {:agent_execution_boundary, params, context}
      assert params == %{test_pid: self(), input: "default", settings: %{second: 3}}
      assert context.request_id == "request-1"
      assert context.agent_id == agent.id
      assert context.agent_state == agent.state
      assert context.signal == signal
    end

    test "rejects caller access to reserved context keys" do
      agent = agent_with_route("counter.add", Add)
      signal = Signal.new!("counter.add", %{by: 1, label: "one"}, source: "/test")

      for key <- [:agent_id, :agent_state, :plugin_inputs, :signal] do
        assert {:error,
                %Jido.Error.ValidationError{
                  message: "Agent command context contains reserved keys"
                }} = Agent.cmd(agent, signal, context: %{key => :replacement})
      end
    end

    test "large caller contexts preserve their fields and reject reserved keys" do
      agent = agent_with_route("counter.observe", ObserveExecutionBoundary)
      signal = Signal.new!("counter.observe", %{test_pid: self()}, source: "/test")
      context = Map.new(1..1_000, &{&1, %{value: &1}})

      assert {:ok, ^agent, []} = Agent.cmd(agent, signal, context: context)
      assert_receive {:agent_execution_boundary, _params, received}
      assert Map.take(received, Map.keys(context)) == context

      for key <- [:agent_id, :agent_state, :plugin_inputs, :signal] do
        assert {:error, %Jido.Error.ValidationError{details: %{keys: [^key]}}} =
                 Agent.cmd(agent, signal, context: Map.put(context, key, nil))
      end

      refute_received {:agent_execution_boundary, _, _}
    end

    test "preserves executable errors without changing the source Agent" do
      agent = agent_with_route("counter.fail", Fail)
      signal = Signal.new!("counter.fail", %{}, source: "/test")

      assert {:error,
              %Jido.Action.Error.ExecutionFailureError{
                details: %{reason: :expected_failure}
              }} = Agent.cmd(agent, signal)

      assert agent.state == %{count: 0, history: []}
    end

    test "rejects invalid complete state output" do
      agent = agent_with_route("counter.invalid", InvalidState)
      signal = Signal.new!("counter.invalid", %{}, source: "/test")

      assert {:error, %{__exception__: true}} = Agent.cmd(agent, signal)
      assert agent.state == %{count: 0, history: []}
    end

    test "returns validated Directives without dispatching them" do
      agent = agent_with_route("counter.stop", WithStopDirective)
      signal = Signal.new!("counter.stop", %{label: "stopped"}, source: "/test")

      assert {:ok, updated, [%Jido.AgentServer.Directive.ServerStop{reason: :normal}]} =
               Agent.cmd(agent, signal)

      assert updated.state == %{count: 0, history: ["stopped"]}
    end

    test "passes execution options to the executable boundary" do
      agent = agent_with_route("counter.block", BlockingAdd)

      signal =
        Signal.new!(
          "counter.block",
          %{by: 1, label: "blocked", test_pid: self(), gate: :offline_timeout},
          source: "/test"
        )

      assert {:error, _reason} = Agent.cmd(agent, signal, timeout: 10)
      assert_receive {:agent_action_blocked, :offline_timeout, _pid}
      assert agent.state == %{count: 0, history: []}
    end

    test "is deterministic for equal Agent, Signal, and option values" do
      agent = agent_with_route("counter.add", Add)
      signal = Signal.new!("counter.add", %{by: 2, label: "same"}, source: "/test")

      assert Agent.cmd(agent, signal, context: %{request_id: "same"}) ==
               Agent.cmd(agent, signal, context: %{request_id: "same"})
    end

    test "runs one Flow as one offline Agent turn" do
      agent = agent_with_route("counter.flow", TwoStepFlow)

      signal =
        Signal.new!(
          "counter.flow",
          %{
            first_by: 2,
            first_label: "first",
            second_by: 3,
            second_label: "second"
          },
          source: "/test"
        )

      assert {:ok, updated, []} = Agent.cmd(agent, signal)
      assert updated.state == %{count: 5, history: ["first", "second"]}
    end
  end

  describe "command and turn values" do
    test "validates the Agent command input value" do
      agent = agent_with_route("counter.add", Add)
      signal = Signal.new!("counter.add", %{}, source: "/test")

      assert {:ok, %Command{agent: ^agent, signal: ^signal, context: %{request_id: "one"}}} =
               Command.new(agent, signal, %{request_id: "one"})

      assert {:error, %{__exception__: true}} = Command.new(:agent, signal)
      assert {:error, %{__exception__: true}} = Command.new(agent, :signal)
      assert {:error, %{__exception__: true}} = Command.new(agent, signal, [])

      assert {:error, %{__exception__: true}} =
               Command.new(%{agent | state: %{count: "invalid"}}, signal)

      assert {:error, %{__exception__: true}} = Command.new(agent, %{signal | id: ""})
      assert {:error, %{__exception__: true}} = Command.validate(:command)
    end

    test "validates Action and Flow turn input values" do
      flow = JidoTest.AgentFixtures.two_step_flow()
      signal = Signal.new!("counter.add", %{by: 1}, source: "/test")

      assert {:ok, %Turn{executable: Add, input: %{by: 1}}} = Turn.new(Add, %{by: 1})
      assert %Turn{executable: ^flow, input: []} = Turn.new!(flow, [])

      assert {:ok, %Turn{source_signal: ^signal}} = Turn.new(Add, %{by: 1}, signal)
      assert %Turn{source_signal: ^signal} = Turn.new!(Add, %{by: 1}, signal)

      assert {:error, %{__exception__: true}} = Turn.new(Add, "invalid input")
      assert {:error, %_{} = _error} = Turn.new(String, %{})

      assert {:error, %{__exception__: true}} =
               Turn.validate(%Turn{executable: Add, input: %{}, source_signal: :invalid})

      assert_raise Jido.Error.ValidationError, fn -> Turn.new!(Add, "invalid input") end
    end
  end

  describe "checkpoint lifecycle" do
    test "runs the complete immutable lifecycle without an Agent Server" do
      definition = AuthoredAgent.definition()
      agent = instance!(definition, id: "offline-1")
      signal = Signal.new!("counter.add", %{by: 2, label: "offline"}, source: "/test")

      assert {:ok, updated, []} = Agent.cmd(agent, signal)
      assert updated.state == %{count: 2, history: ["offline"]}
      assert agent.state == %{count: 0, history: []}

      assert {:ok, checkpoint} = Jido.Persistence.AgentCheckpoint.checkpoint(updated)
      assert {:ok, restored} = Jido.Persistence.AgentCheckpoint.restore(AuthoredAgent, checkpoint)
      assert restored == updated
      assert Agent.definition(restored) == definition
    end

    test "restores direct Agent definitions without a module wrapper" do
      definition = build!(name: "direct_agent", schema: schema())
      agent = instance!(definition, id: "direct-1", state: %{count: 5})

      assert {:ok, checkpoint} = Jido.Persistence.AgentCheckpoint.checkpoint(agent)
      assert {:ok, ^agent} = Jido.Persistence.AgentCheckpoint.restore(Agent, checkpoint)
    end

    test "restores a validated behavior-only Agent module from its checkpoint definition" do
      definition =
        build!(
          name: "behavior_only_agent",
          module: BehaviorOnlyAgent,
          schema: schema()
        )

      agent = instance!(definition, id: "behavior-only-1", state: %{count: 5})

      assert {:ok, checkpoint} = Jido.Persistence.AgentCheckpoint.checkpoint(agent)

      assert {:ok, ^agent} =
               Jido.Persistence.AgentCheckpoint.restore(BehaviorOnlyAgent, checkpoint)
    end

    test "passes context through custom checkpoint and restore callbacks" do
      agent =
        CallbackPersistenceAgent.instantiate!(
          id: "callback-1",
          state: %{count: 7, history: ["before"]}
        )

      assert {:ok, checkpoint} =
               Jido.Persistence.AgentCheckpoint.checkpoint(agent, %{saved_by: "checkpoint"})

      assert checkpoint.format == 1
      assert checkpoint.state_format == :custom
      assert Agent.definition(checkpoint.agent) === Agent.definition(agent)

      assert checkpoint.agent.state == %{
               id: "callback-1",
               state: %{count: 7, history: ["before"]},
               saved_by: "checkpoint"
             }

      assert {:ok, restored} =
               Jido.Persistence.AgentCheckpoint.restore(CallbackPersistenceAgent, checkpoint, %{
                 restored_by: "restore"
               })

      assert restored.id == agent.id
      assert restored.state == %{count: 7, history: ["before", "restore"]}
    end

    test "rejects malformed snapshots before restoring state" do
      agent = CounterAgent.instantiate!(id: "saved")
      assert {:ok, snapshot} = Jido.Persistence.snapshot(agent)

      for invalid <- [
            Map.delete(snapshot, :format),
            %{snapshot | format: 99},
            %{snapshot | state_format: :other},
            %{snapshot | references: %{}},
            %{snapshot | agent: %{agent | id: ""}},
            %{snapshot | agent: %{agent | state: []}},
            %{snapshot | agent: %{agent | vsn: 0}},
            Map.put(snapshot, :extra, nil)
          ] do
        assert {:error, %{__exception__: true}} = Jido.Persistence.restore(invalid)
      end
    end
  end
end
