defmodule Jido.Agent.StateTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent

  defmodule InitializingAgent do
    use Jido.Agent, name: "initializing_agent"

    state do
      schema Zoi.object(%{
               value: Zoi.integer(),
               initialized_for: Zoi.string(),
               defaulted: Zoi.boolean() |> Zoi.default(false)
             })

      initial_state %{value: 1, transient: true}
    end

    @impl Jido.Agent
    def initialize(%{reject: true}, _context), do: {:error, :rejected}

    def initialize(state, %{id: id}),
      do:
        {:ok,
         state
         |> Map.delete(:transient)
         |> Map.update!(:value, &(&1 + 1))
         |> Map.put(:initialized_for, id)}
  end

  def observe(value, _opts) do
    send(self(), {:validated, value})
    :ok
  end

  @tag obligation: ["jido.agent.I6", "jido.agent.I8"]
  test "the callback transforms declared and explicit state before schema defaults" do
    definition = InitializingAgent.definition()
    assert definition.initial_state == %{value: 1, transient: true}
    initialized = InitializingAgent.instantiate!(id: "initialized")
    assert initialized.state == %{value: 2, initialized_for: "initialized", defaulted: false}
    overridden = InitializingAgent.instantiate!(id: "overridden", state: %{value: 3})
    assert overridden.state == %{value: 4, initialized_for: "overridden", defaulted: false}
    assert {:ok, ^overridden} = Agent.validate(overridden)

    assert {:error, %Agent.Error{code: :initialize_failed, details: %{reason: :rejected}}} =
             InitializingAgent.instantiate(id: "error", state: %{reject: true})
  end

  @tag obligation: "jido.agent.I8"
  test "initialization validates unchanged state once" do
    schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}) |> Zoi.default(0)
      })

    definition = Agent.define!(%{name: "single_validation", schema: schema})

    for overrides <- [[], [state: %{count: 4}]] do
      assert {:ok, agent} = Agent.instantiate(definition, Keyword.put(overrides, :id, "observe"))
      assert_received {:validated, value}
      assert value == agent.state.count
      refute_received {:validated, _}
    end
  end

  @tag obligation: ["jido.agent.I6", "jido.agent.I8"]
  test "initial state can be partial and the merged state uses one schema validation" do
    schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}),
        enabled: Zoi.boolean() |> Zoi.default(true)
      })

    definition =
      Agent.define!(%{
        name: "partial_initial_state",
        schema: schema,
        initial_state: %{enabled: false}
      })

    assert {:ok, agent} =
             Agent.instantiate(definition,
               id: Jido.Signal.ID.generate!(),
               state: %{count: 3}
             )

    assert agent.state === %{count: 3, enabled: false}
    assert_received {:validated, 3}
    refute_received {:validated, _}

    invalid = %{definition | initial_state: %{enabled: "false"}}
    assert {:error, %Jido.Agent.Error{path: [:state]}} = Agent.instantiate(invalid, id: "bad")
  end

  @tag obligation: "jido.agent.I8"
  test "defaults and explicit nil cannot insert invalid values" do
    for schema <- [
          Zoi.object(%{count: Zoi.integer() |> Zoi.default("invalid")}),
          Zoi.object(%{nested: Zoi.object(%{count: Zoi.integer() |> Zoi.default("invalid")})})
        ],
        state <- [%{}, %{count: nil}, %{nested: %{}}] do
      definition = Agent.define!(%{name: "invalid_default", schema: schema})

      assert {:error, %{__exception__: true}} =
               Agent.instantiate(definition, id: Jido.Signal.ID.generate!(), state: state)
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "initialization retains nested defaults, explicit nil, and supplied values" do
    schema =
      Zoi.object(%{
        config: Zoi.map() |> Zoi.default(%{first: 1, second: 2}),
        count: Zoi.integer() |> Zoi.default(3),
        optional: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
      })

    definition = Agent.define!(%{name: "nested_defaults", schema: schema})

    assert {:ok, agent} =
             Agent.instantiate(definition,
               id: Jido.Signal.ID.generate!(),
               state: %{config: %{second: 4}, count: nil}
             )

    assert agent.state == %{config: %{second: 4}, count: 3, optional: nil}

    assert {:error, %Jido.Agent.Error{code: :incomplete_state}} =
             Agent.transition(agent, %{optional: nil})
  end

  def mutate(value, opts) do
    send(self(), {:mutated, value})
    %{opts[:ctx] | valid?: true, parsed: value + 1}
  end

  def increment(value, _opts) do
    send(self(), {:transformed, value})
    value + 1
  end

  @tag obligation: "jido.agent.I8"
  test "nested defaults reach the leaf and validate it once" do
    for depth <- [0, 1, 2, 64, 70] do
      leaf = Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}) |> Zoi.default(1)

      nested =
        Enum.reduce(1..depth//1, leaf, fn _, child ->
          Zoi.object(%{child: child}) |> Zoi.default(%{})
        end)

      expected = Enum.reduce(1..depth//1, 1, fn _, child -> %{child: child} end)
      definition = Agent.define!(%{name: "deep_defaults", schema: Zoi.object(%{root: nested})})
      assert {:ok, agent} = Agent.instantiate(definition, id: Jido.Signal.ID.generate!())
      assert agent.state === %{root: expected}
      assert_received {:validated, 1}
      refute_received {:validated, _}
      assert {:ok, ^agent} = Agent.validate(agent)
      assert_received {:validated, 1}
      refute_received {:validated, _}
    end
  end

  @tag obligation: "jido.agent.I8"
  test "deep invalid defaults fail during initialization" do
    for depth <- [0, 1, 2, 64, 70] do
      leaf = Zoi.integer() |> Zoi.default("bad")

      nested =
        Enum.reduce(1..depth//1, leaf, fn _, child ->
          Zoi.object(%{child: child}) |> Zoi.default(%{})
        end)

      definition =
        Agent.define!(%{name: "deep_invalid_defaults", schema: Zoi.object(%{root: nested})})

      assert {:error, %Jido.Agent.Error{details: %{issues: [%Zoi.Error{path: path}]}}} =
               Agent.instantiate(definition, id: Jido.Signal.ID.generate!())

      assert path == [:root | List.duplicate(:child, depth)]
    end
  end

  @tag obligation: "jido.agent.I9"
  test "state schemas reject transforms and coercion before callbacks run" do
    for field <- [
          Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []}),
          Zoi.integer(coerce: true),
          Zoi.list(Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []})),
          Zoi.union([Zoi.integer(), Zoi.string(coerce: true)])
        ] do
      schema = Zoi.object(%{nested: Zoi.object(%{value: field})})

      assert {:error, %Jido.Agent.Error{path: [:schema | _]}} =
               Agent.define(%{name: "invalid_schema", schema: schema})

      refute_received {:transformed, _}
    end
  end

  @tag obligation: "jido.agent.I9"
  test "input conversion types and dynamic schemas cannot bypass the state contract" do
    for field <- [Zoi.string_boolean(), Zoi.lazy({__MODULE__, :lazy_transform, []})] do
      assert {:error, %Jido.Agent.Error{path: [:schema | _]}} =
               Agent.define(%{name: "conversion_schema", schema: Zoi.object(%{value: field})})

      refute_received :lazy_schema_called
    end
  end

  def lazy_transform do
    send(self(), :lazy_schema_called)
    Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []})
  end

  @tag obligation: "jido.agent.I8"
  test "a successful refinement cannot change initialized state" do
    schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.refine({__MODULE__, :mutate, []}) |> Zoi.default(1)
      })

    definition = Agent.define!(%{name: "mutating_refinement", schema: schema})

    assert {:error, %{__exception__: true}} =
             Agent.instantiate(definition, id: Jido.Signal.ID.generate!())

    assert_received {:mutated, 1}
    refute_received {:mutated, _}
  end

  @tag obligation: "jido.agent.I9"
  test "stored state checks do not fill defaults or replace explicit nil" do
    schema =
      Zoi.object(%{
        nested: Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)}) |> Zoi.default(%{})
      })

    definition = Agent.define!(%{name: "stored_defaults", schema: schema})
    agent = Agent.instantiate!(definition, id: Jido.Signal.ID.generate!())
    assert agent.state === %{nested: %{count: 1}}

    for state <- [%{}, %{nested: %{}}, %{nested: nil}, %{nested: %{count: nil}}] do
      assert {:error, %{__exception__: true}} =
               Agent.validate(%{agent | state: state})

      assert {:error, %{__exception__: true}} = Agent.transition(agent, state)
      assert agent.state === %{nested: %{count: 1}}
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "optional defaulted fields stay absent in input and stored state" do
    schema = Zoi.object(%{count: Zoi.integer() |> Zoi.default(1) |> Zoi.optional()})
    definition = Agent.define!(%{name: "optional_default", schema: schema})
    agent = Agent.instantiate!(definition, id: Jido.Signal.ID.generate!())
    assert agent.state === %{}
    assert {:ok, ^agent} = Agent.validate(agent)
    assert {:ok, ^agent} = Agent.transition(agent, %{})

    assert {:ok, %{state: %{count: 1}}} =
             Agent.instantiate(definition, id: Jido.Signal.ID.generate!(), state: %{count: nil})

    assert {:error, _} = Agent.transition(agent, %{count: nil})
  end

  @tag obligation: "jido.agent.I8"
  test "nil defaults need a nullable schema" do
    for nullable? <- [false, true] do
      field = if nullable?, do: Zoi.integer() |> Zoi.nullable(), else: Zoi.integer()

      definition =
        Agent.define!(%{
          name: "nil_default",
          schema: Zoi.object(%{count: Zoi.default(field, nil)})
        })

      if nullable? do
        assert {:ok, %{state: %{count: nil}} = agent} =
                 Agent.instantiate(definition, id: Jido.Signal.ID.generate!())

        assert {:ok, ^agent} = Agent.validate(agent)
      else
        assert {:error, %{__exception__: true}} =
                 Agent.instantiate(definition, id: Jido.Signal.ID.generate!())
      end
    end
  end

  @tag obligation: "jido.agent.I9"
  test "stored checks cannot silently strip nested keys" do
    schema = Zoi.object(%{nested: Zoi.map(%{count: Zoi.integer()})})
    definition = Agent.define!(%{name: "stored_unknown", schema: schema})

    agent =
      Agent.instantiate!(definition,
        id: Jido.Signal.ID.generate!(),
        state: %{nested: %{count: 1}}
      )

    assert {:error, _} = Agent.transition(agent, %{nested: %{count: 1, other: 2}})
    assert {:ok, ^agent} = Agent.validate(agent)
  end

  defmodule TransformPlugin do
    use Jido.Plugin
    @impl true
    def state_spec(_opts),
      do:
        {:plugin_count,
         Zoi.integer() |> Zoi.transform({Jido.Agent.StateTest, :increment, []}) |> Zoi.default(1)}
  end

  @tag obligation: "jido.agent.I10"
  test "composed Plugin state follows the same schema policy" do
    assert {:error, %Jido.Agent.Error{path: [:schema | _]}} =
             Agent.define(%{
               name: "plugin_transform",
               extensions: [
                 %{
                   id: TransformPlugin.id(),
                   provider: TransformPlugin,
                   vsn: TransformPlugin.vsn(),
                   data: %{}
                 }
               ]
             })

    refute_received {:transformed, _}
  end
end
