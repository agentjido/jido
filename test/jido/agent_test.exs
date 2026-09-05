defmodule Jido.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.Agent.Directive
  alias Jido.Agent.Turn
  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal
  alias Jido.Signal.ID
  alias Jido.Signal.Router

  alias JidoTest.AgentFixtures.{
    Add,
    BlockingAdd,
    CounterAgent,
    Fail,
    InvalidBehavior,
    InvalidState,
    ObserveExecutionBoundary
  }

  defmodule AuthoredAgent do
    @moduledoc false

    use Jido.Agent,
      name: "authored_agent",
      description: "Exercises the generated Agent API",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([])
        }),
      routes: [{"counter.add", JidoTest.AgentFixtures.Add}],
      metadata: %{category: "test", tags: ["agent", "immutable"], vsn: "1.0.0"}
  end

  defmodule InvalidRouteAgent do
    @moduledoc false

    use Jido.Agent,
      name: "invalid_route_agent",
      routes: [{"invalid.route", String}]
  end

  defmodule CustomRoutingAgent do
    @moduledoc false

    use Jido.Agent,
      name: "custom_routing_agent",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([])
        })

    @impl Jido.Agent
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

    @impl Jido.Agent
    def handle_signal(_signal, _agent), do: :invalid_callback_result
  end

  defmodule WithStopDirective do
    @moduledoc false

    use Jido.Action, name: "agent_with_stop_directive"

    @impl Jido.Action
    def run(%{label: label}, context) do
      state = %{context.agent_state | history: context.agent_state.history ++ [label]}
      {:ok, state, [%Jido.Agent.Directive.Stop{reason: :normal}]}
    end
  end

  defmodule CallbackPersistenceAgent do
    @moduledoc false

    use Jido.Agent,
      name: "callback_persistence_agent",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([])
        })

    @impl Jido.Agent
    def checkpoint(agent, context) do
      {:ok, %{id: agent.id, state: agent.state, saved_by: context.saved_by}}
    end

    @impl Jido.Agent
    def restore(checkpoint, context) do
      state = Map.update!(checkpoint.state, :history, &(&1 ++ [context.restored_by]))
      new(id: checkpoint.id, state: state)
    end
  end

  defmodule FaultyPersistenceAgent do
    @moduledoc false

    use Jido.Agent, name: "faulty_persistence_agent"

    @impl Jido.Agent
    def checkpoint(_agent, %{result: result}), do: result

    def checkpoint(_agent, %{failure: :raise}), do: raise("checkpoint failed")
    def checkpoint(_agent, %{failure: :throw}), do: throw(:checkpoint_failed)
    def checkpoint(agent, context), do: Jido.Agent.default_checkpoint(agent, context)

    @impl Jido.Agent
    def restore(_checkpoint, %{result: result}), do: result

    def restore(_checkpoint, %{failure: :raise}), do: raise("restore failed")
    def restore(_checkpoint, %{failure: :throw}), do: throw(:restore_failed)

    def restore(checkpoint, context),
      do: Jido.Agent.default_restore(__MODULE__, checkpoint, context)
  end

  defp schema do
    Zoi.object(%{
      count: Zoi.integer() |> Zoi.default(0),
      history: Zoi.list(Zoi.string()) |> Zoi.default([])
    })
  end

  defp agent_with_route(path, target) do
    Agent.new!(name: "counter", schema: schema(), routes: [{path, target}])
    |> Agent.instantiate!()
  end

  test "builds one neutral canonical Agent definition" do
    definition =
      Agent.new!(
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
             plugins: [],
             state: nil
           } = definition

    assert agent_schema == schema()
    assert [%Router.Route{path: "counter.add", target: Add}] = definition.routes
    assert Agent.definition?(definition)
    refute Agent.instance?(definition)

    assert definition
           |> Map.from_struct()
           |> Map.keys()
           |> Enum.sort() ==
             Enum.sort([
               :id,
               :module,
               :name,
               :description,
               :schema,
               :plugins,
               :state,
               :routes,
               :metadata
             ])
  end

  test "instantiates one definition with identity and schema defaults" do
    definition = Agent.new!(name: "counter", schema: schema())

    agent = Agent.instantiate!(definition, id: "counter-1")

    assert agent.id == "counter-1"
    assert agent.state == %{count: 0, history: []}
    assert agent.module == Agent
    assert Agent.instance?(agent)
    refute Agent.definition?(agent)
    assert Agent.definition(agent) == definition
    assert definition.id == nil
    assert definition.state == nil
  end

  test "keeps definitions out of instance-only operations" do
    definition =
      Agent.new!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])

    signal = Signal.new!("counter.add", %{by: 1}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{}} = Agent.transition(definition, %{})
    assert {:error, %Jido.Error.ValidationError{}} = Agent.checkpoint(definition)
    assert {:error, %Jido.Error.ValidationError{}} = Agent.cmd(definition, signal)

    instance = Agent.instantiate!(definition)

    assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(instance)
  end

  test "rejects instance data at the definition boundary and half-instances" do
    definition = Agent.new!(name: "counter", schema: schema())

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.new(name: "counter", id: "counter-1")

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.new(name: "counter", state: %{count: 0, history: []})

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.validate(%{definition | id: "counter-1"})

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.validate(%{definition | state: %{count: 0, history: []}})
  end

  test "defines Agent values and callback values with Zoi structs" do
    assert %Zoi.Types.Struct{module: Agent} = Agent.schema()
    assert %Zoi.Types.Struct{module: Turn} = Turn.schema()
    assert %Zoi.Types.Struct{module: Outcome} = Outcome.schema()
  end

  test "validates terminal Turn outcomes" do
    signal = Signal.new!("counter.add", %{by: 1}, source: "/test")
    id = ID.generate!()

    attrs = %{
      id: id,
      agent_id: "counter-1",
      source_signal: signal,
      effective_signal: signal,
      status: :failed,
      stage: :execute,
      committed?: false,
      state_version_before: 0,
      error: :simulated_failure,
      directives: %{total: 0, completed: 0, failed: 0, failed_index: nil, skipped: 0},
      started_at: 10,
      finished_at: 12,
      duration_ms: 2
    }

    assert {:ok, %Outcome{status: :failed} = outcome} = Outcome.new(attrs)

    assert {:ok, ^outcome} = Outcome.new(outcome)

    assert {:error, %Jido.Error.ValidationError{}} =
             Outcome.new(%{outcome | id: "not-a-turn-id"})

    assert {:error, %Jido.Error.ValidationError{}} =
             Outcome.new(%{
               attrs
               | status: :succeeded,
                 stage: :commit,
                 committed?: true,
                 error: nil
             })

    assert {:error, %Jido.Error.ValidationError{}} =
             Outcome.new(%{attrs | status: :succeeded, error: :contradiction})

    assert {:error, %Jido.Error.ValidationError{}} =
             Outcome.new(%{attrs | stage: :directive})

    assert {:error, %Jido.Error.ValidationError{}} =
             Outcome.new(%{attrs | finished_at: 9})
  end

  test "builds instances from a module that uses Jido.Agent" do
    definition = CounterAgent.agent()
    agent = CounterAgent.new!(state: %{count: 4, history: ["existing"]})

    assert %Agent{id: nil, state: nil, module: CounterAgent} = definition

    assert %Agent{
             module: CounterAgent,
             name: "counter_agent",
             description: "A module-authored Agent",
             state: %{count: 4, history: ["existing"]}
           } = agent

    assert CounterAgent.name() == "counter_agent"
    assert CounterAgent.description() == "A module-authored Agent"
    assert CounterAgent.schema() == agent.schema
    assert [%Router.Route{path: "counter.add", target: Add}] = CounterAgent.routes()
    assert CounterAgent.plugins() == []
    assert Agent.definition(agent) == definition

    assert {:error, %Jido.Error.ValidationError{}} = CounterAgent.new(name: "changed")
  end

  test "rejects an invalid behavior, schema, route, and initial state" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.new(name: "counter", module: InvalidBehavior)

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.new(name: "counter", schema: Zoi.string())

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.new(name: "counter", routes: [{"counter.add", String}])

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.new(name: "counter", schema: schema(), id: "bad", state: %{count: "bad"})

    definition = Agent.new!(name: "counter", schema: schema())

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.instantiate(definition, state: %{count: "bad"})
  end

  test "plans one executable from one Signal without exposing Server state" do
    agent =
      Agent.new!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])
      |> Agent.instantiate!()

    signal = Signal.new!(type: "counter.add", source: "/test", data: %{by: 2, label: "one"})

    assert {:ok,
            %Turn{
              executable: Add,
              input: %{by: 2, label: "one"}
            }} = Agent.handle_signal(signal, agent)
  end

  test "requires one Signal to resolve to exactly one executable" do
    agent =
      Agent.new!(
        name: "counter",
        schema: schema(),
        routes: [{"counter.*", Add}, {"counter.add", Add}]
      )
      |> Agent.instantiate!()

    signal = Signal.new!(type: "counter.add", source: "/test", data: %{})
    assert {:error, %Jido.Error.RoutingError{}} = Agent.handle_signal(signal, agent)
  end

  test "replaces and validates the complete Agent state" do
    agent = Agent.new!(name: "counter", schema: schema()) |> Agent.instantiate!()

    assert {:ok, next} = Agent.transition(agent, %{count: 3, history: ["done"]})
    assert next.state == %{count: 3, history: ["done"]}
    assert next.id == agent.id
    assert next.schema == agent.schema

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.transition(agent, %{count: :invalid, history: []})
  end

  test "merges an explicit data mutation through the Agent schema" do
    agent = Agent.new!(name: "counter", schema: schema()) |> Agent.instantiate!()

    assert {:ok, next} = Agent.set(agent, count: 4)
    assert next.state == %{count: 4, history: []}
    assert agent.state == %{count: 0, history: []}

    assert {:error, %Jido.Error.ValidationError{}} = Agent.set(agent, count: :invalid)
  end

  test "applies the same executable turn to an Agent value without a process" do
    agent =
      Agent.new!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])
      |> Agent.instantiate!()

    signal = Signal.new!("counter.add", %{by: 2, label: "offline"}, source: "/test")

    assert {:ok, next, []} = Agent.cmd(agent, signal, timeout: 1_000)
    assert next.state == %{count: 2, history: ["offline"]}
    assert agent.state == %{count: 0, history: []}
  end

  test "an Agent module exposes the same cmd API" do
    agent = CounterAgent.new!()
    signal = Signal.new!("counter.add", %{by: 3, label: "module"}, source: "/test")

    assert {:ok, next, []} = CounterAgent.cmd(agent, signal)
    assert next.state == %{count: 3, history: ["module"]}
  end

  test "rejects invalid offline caller context with a validation error" do
    agent =
      Agent.new!(name: "counter", schema: schema(), routes: [{"counter.add", Add}])
      |> Agent.instantiate!()

    signal = Signal.new!("counter.add", %{by: 1, label: "invalid"}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{}} =
             Agent.cmd(agent, signal, context: "not a context")
  end

  test "separates portable definition data from instance data" do
    first = CounterAgent.new!(id: "first", state: %{count: 1})
    second = CounterAgent.new!(id: "second", state: %{count: 8})

    assert Agent.definition(first) == Agent.definition(second)
    assert %Agent{id: nil, state: nil} = Agent.definition(first)
  end

  test "checkpoints and restores only Agent domain data" do
    agent = CounterAgent.new!(id: "saved", state: %{count: 7, history: ["saved"]})

    assert {:ok, checkpoint} = Agent.checkpoint(agent)
    assert checkpoint.kind == :agent
    assert checkpoint.agent_module == CounterAgent
    assert checkpoint.definition == CounterAgent.agent()
    assert %Agent{id: nil, state: nil} = checkpoint.definition
    assert checkpoint.state == agent.state

    assert {:ok, restored} = Agent.restore(CounterAgent, checkpoint)
    assert restored == agent
  end

  describe "module authoring API" do
    test "exposes canonical definition data through generated accessors" do
      definition = AuthoredAgent.agent()

      assert AuthoredAgent.name() == "authored_agent"
      assert AuthoredAgent.description() == "Exercises the generated Agent API"
      assert AuthoredAgent.domain_schema() == definition.schema
      assert AuthoredAgent.schema() == definition.schema
      assert AuthoredAgent.complete_schema() == definition.schema
      assert AuthoredAgent.routes() == definition.routes
      assert AuthoredAgent.plugins() == definition.plugins

      assert AuthoredAgent.metadata() == %{
               category: "test",
               tags: ["agent", "immutable"],
               vsn: "1.0.0"
             }
    end

    test "rejects dynamic Agent state schemas" do
      anonymous_schema =
        Zoi.object(%{value: Zoi.string() |> Zoi.refine(fn _value -> :ok end)})

      lazy_schema = Zoi.object(%{value: Zoi.lazy(fn -> Zoi.string() end)})

      assert {:error,
              %Jido.Error.ValidationError{message: "Agent schema must contain static data"}} =
               Agent.new(name: "anonymous_schema_agent", schema: anonymous_schema)

      assert {:error,
              %Jido.Error.ValidationError{message: "Agent schema must contain static data"}} =
               Agent.new(name: "lazy_schema_agent", schema: lazy_schema)
    end

    test "validates module-authored route targets before instantiation" do
      assert {:error, %Jido.Error.ValidationError{message: "Invalid Agent route executable"}} =
               InvalidRouteAgent.new()
    end
  end

  describe "definition construction" do
    test "accepts maps, keyword lists, and an existing definition" do
      attrs = %{name: "direct_agent", description: "Direct definition", metadata: %{tier: 1}}

      assert {:ok, from_map} = Agent.new(attrs)
      assert {:ok, from_keyword} = Agent.new(Map.to_list(attrs))
      assert {:ok, validated} = Agent.new(from_map)

      assert from_map == from_keyword
      assert validated == from_map
    end

    test "rejects unknown definition keys and invalid definition data" do
      assert {:error,
              %Jido.Error.ValidationError{
                message: "Unknown Agent definition key",
                details: %{key: :unknown}
              }} = Agent.new(name: "bad_agent", unknown: true)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.new(name: "bad_agent", description: 123)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.new(name: "bad_agent", metadata: Date.utc_today())

      assert {:error, %Jido.Error.ValidationError{}} = Agent.new([:not_a_keyword_list])
      assert {:error, %Jido.Error.ValidationError{}} = Agent.new(:not_definition_data)
    end

    test "raising constructors raise the returned validation error" do
      assert_raise Jido.Error.ValidationError, fn ->
        Agent.new!(name: "invalid_agent", schema: Zoi.string())
      end

      definition = Agent.new!(name: "valid_agent")

      assert_raise Jido.Error.ValidationError, fn ->
        Agent.instantiate!(definition, id: "")
      end
    end

    test "converts canonical routes to portable map data" do
      agent = AuthoredAgent.new!(id: "mapped", state: %{count: 2})

      assert %{
               id: "mapped",
               module: AuthoredAgent,
               name: "authored_agent",
               state: %{count: 2, history: []},
               routes: [
                 %{path: "counter.add", target: Add, priority: 0, match: nil}
               ]
             } = Agent.to_map(agent)
    end
  end

  describe "instance lifecycle" do
    test "generates non-empty unique identities and accepts an explicit identity" do
      definition = Agent.new!(name: "identity_agent")

      first = Agent.instantiate!(definition)
      second = Agent.instantiate!(definition, id: nil)
      explicit = Agent.instantiate!(definition, id: "agent-123")

      assert is_binary(first.id) and first.id != ""
      assert is_binary(second.id) and second.id != ""
      assert first.id != second.id
      assert explicit.id == "agent-123"

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.instantiate(definition, id: "")

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.instantiate(definition, id: 123)
    end

    test "merges partial initial state over schema defaults" do
      definition = Agent.new!(name: "counter", schema: schema())

      assert {:ok, agent} = Agent.instantiate(definition, state: %{count: 9})
      assert agent.state == %{count: 9, history: []}
    end

    test "accepts only identity and state instance overrides" do
      definition = Agent.new!(name: "counter", schema: schema())

      assert {:error,
              %Jido.Error.ValidationError{
                message: "Agent instances can set only :id and :state"
              }} = Agent.instantiate(definition, name: "replacement")

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.instantiate(definition, [:not_a_keyword_list])
    end

    test "validates definitions and instances through explicit boundaries" do
      definition = Agent.new!(name: "counter", schema: schema())
      agent = Agent.instantiate!(definition, id: "counter-1")

      assert {:ok, ^definition} = Agent.validate(definition)
      assert {:ok, ^definition} = Agent.validate_definition(definition)
      assert {:ok, ^agent} = Agent.validate(agent)
      assert {:ok, ^agent} = Agent.validate_instance(agent)

      assert {:error, %Jido.Error.ValidationError{}} = Agent.validate_definition(agent)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.validate_instance(definition)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.validate(:not_an_agent)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.validate(%{agent | state: %{count: "invalid", history: []}})
    end

    test "rejects unknown state keys at construction and transition boundaries" do
      definition = Agent.new!(name: "counter", schema: schema())

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.instantiate(definition, state: %{extra: true})

      agent = Agent.instantiate!(definition)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.transition(agent, %{count: 0, history: [], extra: true})
    end

    test "deep merges domain state and keeps the source Agent immutable" do
      nested_schema =
        Zoi.object(%{
          config: Zoi.map() |> Zoi.default(%{a: 1, b: 2})
        })

      agent =
        Agent.new!(name: "nested_agent", schema: nested_schema)
        |> Agent.instantiate!()

      assert {:ok, updated} = Agent.set(agent, config: %{b: 3, c: 4})
      assert updated.state.config == %{a: 1, b: 3, c: 4}
      assert agent.state.config == %{a: 1, b: 2}
    end

    test "returns a validation error for malformed set attributes" do
      agent = Agent.new!(name: "counter", schema: schema()) |> Agent.instantiate!()

      assert {:error, %Jido.Error.ValidationError{}} = Agent.set(agent, [:not_a_keyword_list])
    end
  end

  describe "Signal and command lifecycle" do
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

    test "normalizes missing routes, invalid routes, and invalid Signal types" do
      agent = agent_with_route("counter.add", Add)
      signal = Signal.new!("counter.unknown", %{}, source: "/test")
      router = Router.new!(agent.routes)

      for {type, reason} <- [
            {"counter.unknown", :no_handlers_found},
            {nil, :nil_signal_type},
            {:invalid, :invalid_signal_type}
          ] do
        command = %{signal | type: type}
        assert {:error, %Jido.Signal.Error.RoutingError{}} = Router.route(router, command)

        for result <- [Agent.handle_signal(command, agent), Agent.cmd(agent, command)] do
          assert {:error,
                  %Jido.Error.RoutingError{
                    target: ^type,
                    details: %{reason: ^reason, cause: cause}
                  } = error} = result

          assert %Jido.Signal.Error.RoutingError{} = cause
          assert error.message == cause.message
          assert Map.take(error.details, Map.keys(cause.details)) == cause.details
        end
      end

      invalid_agent = %{agent | routes: [{"counter..invalid", Add}]}

      for result <- [
            Agent.handle_signal(signal, invalid_agent),
            Agent.cmd(invalid_agent, signal)
          ] do
        assert {:error,
                %Jido.Error.RoutingError{
                  target: "counter.unknown",
                  details: %{route: "counter..invalid", cause: cause}
                }} = result

        assert %Jido.Signal.Error.RoutingError{} = cause
      end
    end

    test "preserves custom routing error details, cause, and retry hints" do
      agent = CustomRoutingAgent.new!()

      for retry <- [true, false] do
        cause =
          Jido.Signal.Error.routing_error("Custom route unavailable", %{
            target: "custom.target",
            route: "custom.routing_failure",
            retry: retry,
            reason: :unavailable
          })

        signal = Signal.new!("custom.routing_failure", %{error: cause}, source: "/test")

        assert {:error, %Jido.Error.RoutingError{} = error} = Agent.cmd(agent, signal)
        assert error.message == cause.message
        assert error.target == "custom.target"
        assert error.details == Map.put(cause.details, :cause, cause)
        assert Jido.Error.retryable?(error) == retry
      end

      error = Jido.Error.routing_error("Already normalized", target: "custom.target")
      signal = Signal.new!("custom.routing_failure", %{error: error}, source: "/test")
      assert {:error, ^error} = Agent.cmd(agent, signal)
    end

    test "supports one custom handle_signal callback as the routing boundary" do
      agent = CustomRoutingAgent.new!()
      signal = Signal.new!("custom.add", %{by: 3}, source: "/test")

      assert {:ok, updated, []} = CustomRoutingAgent.cmd(agent, signal)
      assert updated.state == %{count: 3, history: ["custom"]}

      unsupported = Signal.new!("custom.unknown", %{}, source: "/test")
      assert {:error, :unsupported_signal} = CustomRoutingAgent.cmd(agent, unsupported)
    end

    test "contains an invalid handle_signal callback result" do
      agent = InvalidCallbackAgent.new!()
      signal = Signal.new!("invalid.callback", %{}, source: "/test")

      assert {:error,
              %Jido.Error.ExecutionError{
                message: "Agent handle_signal/2 returned an invalid result"
              }} = InvalidCallbackAgent.cmd(agent, signal)
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

    test "rejects caller and Plugin access to reserved context keys" do
      agent = agent_with_route("counter.add", Add)
      signal = Signal.new!("counter.add", %{by: 1, label: "one"}, source: "/test")

      for key <- [:agent_id, :agent_state, :signal] do
        assert {:error,
                %Jido.Error.ValidationError{
                  message: "Agent command context contains reserved keys"
                }} = Agent.cmd(agent, signal, context: %{key => :replacement})
      end
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

      assert {:error, %Jido.Error.ValidationError{}} = Agent.cmd(agent, signal)
      assert agent.state == %{count: 0, history: []}
    end

    test "returns validated Directives without dispatching them" do
      agent = agent_with_route("counter.stop", WithStopDirective)
      signal = Signal.new!("counter.stop", %{label: "stopped"}, source: "/test")

      assert {:ok, updated, [%Directive.Stop{reason: :normal}]} = Agent.cmd(agent, signal)
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
      agent = agent_with_route("counter.flow", JidoTest.AgentFixtures.two_step_flow())

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

      assert {:error, %Jido.Error.ValidationError{}} = Command.new(:agent, signal)
      assert {:error, %Jido.Error.ValidationError{}} = Command.new(agent, :signal)
      assert {:error, %Jido.Error.ValidationError{}} = Command.new(agent, signal, [])
      assert {:error, %Jido.Error.ValidationError{}} = Command.validate(:command)
    end

    test "validates Action and Flow turn input values" do
      flow = JidoTest.AgentFixtures.two_step_flow()

      assert {:ok, %Turn{executable: Add, input: %{by: 1}}} = Turn.new(Add, %{by: 1})
      assert %Turn{executable: ^flow, input: []} = Turn.new!(flow, [])

      assert {:error, %Jido.Error.ValidationError{}} = Turn.new(Add, "invalid input")
      assert {:error, %_{} = _error} = Turn.new(String, %{})

      assert_raise Jido.Error.ValidationError, fn -> Turn.new!(Add, "invalid input") end
    end
  end

  describe "checkpoint lifecycle" do
    test "runs the complete immutable lifecycle without an Agent Server" do
      definition = AuthoredAgent.agent()
      agent = Agent.instantiate!(definition, id: "offline-1")
      signal = Signal.new!("counter.add", %{by: 2, label: "offline"}, source: "/test")

      assert {:ok, updated, []} = Agent.cmd(agent, signal)
      assert updated.state == %{count: 2, history: ["offline"]}
      assert agent.state == %{count: 0, history: []}

      assert {:ok, checkpoint} = Agent.checkpoint(updated)
      assert {:ok, restored} = Agent.restore(AuthoredAgent, checkpoint)
      assert restored == updated
      assert Agent.definition(restored) == definition
    end

    test "restores direct Agent definitions without a module wrapper" do
      definition = Agent.new!(name: "direct_agent", schema: schema())
      agent = Agent.instantiate!(definition, id: "direct-1", state: %{count: 5})

      assert {:ok, checkpoint} = Agent.checkpoint(agent)
      assert {:ok, ^agent} = Agent.restore(Agent, checkpoint)
    end

    test "passes context through custom checkpoint and restore callbacks" do
      agent =
        CallbackPersistenceAgent.new!(
          id: "callback-1",
          state: %{count: 7, history: ["before"]}
        )

      assert {:ok, checkpoint} = Agent.checkpoint(agent, %{saved_by: "checkpoint"})
      assert checkpoint.saved_by == "checkpoint"

      assert {:ok, restored} =
               Agent.restore(CallbackPersistenceAgent, checkpoint, %{restored_by: "restore"})

      assert restored.id == agent.id
      assert restored.state == %{count: 7, history: ["before", "restore"]}
    end

    test "rejects malformed default checkpoints" do
      agent = CounterAgent.new!(id: "saved")
      assert {:ok, checkpoint} = Agent.checkpoint(agent)

      malformed = [
        Map.delete(checkpoint, :version),
        %{checkpoint | version: 2},
        %{checkpoint | kind: :other},
        %{checkpoint | agent_module: Agent},
        %{checkpoint | id: ""},
        %{checkpoint | state: []}
      ]

      for invalid <- malformed do
        assert {:error, %Jido.Error.ValidationError{}} = Agent.restore(CounterAgent, invalid)
      end

      direct = Agent.new!(name: "direct_agent") |> Agent.instantiate!(id: "direct-1")
      assert {:ok, direct_checkpoint} = Agent.checkpoint(direct)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.restore(Agent, %{direct_checkpoint | definition: :invalid})
    end

    test "contains callback failures and invalid return contracts" do
      agent = FaultyPersistenceAgent.new!(id: "faulty-1")
      assert {:ok, checkpoint} = Agent.checkpoint(agent)

      assert {:error, {:checkpoint, :invalid_return, :invalid}} =
               Agent.checkpoint(agent, %{result: :invalid})

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.checkpoint(agent, %{result: {:ok, :not_a_map}})

      assert {:error, {:checkpoint, :raised, %RuntimeError{}}} =
               Agent.checkpoint(agent, %{failure: :raise})

      assert {:error, {:checkpoint, :throw, :checkpoint_failed}} =
               Agent.checkpoint(agent, %{failure: :throw})

      assert {:error, {:restore, :invalid_return, :invalid}} =
               Agent.restore(FaultyPersistenceAgent, checkpoint, %{result: :invalid})

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.restore(FaultyPersistenceAgent, checkpoint, %{result: {:ok, :not_an_agent}})

      assert {:error,
              %Jido.Error.ValidationError{message: "Restored Agent module does not match"}} =
               Agent.restore(FaultyPersistenceAgent, checkpoint, %{
                 result: {:ok, CounterAgent.new!(id: "other-agent")}
               })

      assert {:error, {:restore, :raised, %RuntimeError{}}} =
               Agent.restore(FaultyPersistenceAgent, checkpoint, %{failure: :raise})

      assert {:error, {:restore, :throw, :restore_failed}} =
               Agent.restore(FaultyPersistenceAgent, checkpoint, %{failure: :throw})
    end
  end
end
