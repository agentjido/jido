defmodule Jido.Agent.StateTest do
  use Covenant.Case, component: "jido.agent", async: true

  alias Jido.Agent

  defmodule InitializingAgent do
    use Jido.Agent, name: "initializing_agent"

    state do
      schema Jido.Joi.object(%{
               value: Jido.Joi.integer(),
               initialized_for: Jido.Joi.string(),
               defaulted: Jido.Joi.boolean() |> Jido.Joi.default(false)
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

    assert {:error, %Jido.Error.ValidationError{code: :initialize_failed, details: %{reason: :rejected}}} =
             InitializingAgent.instantiate(id: "error", state: %{reject: true})
  end

  @tag obligation: "jido.agent.I8"
  test "initialization validates unchanged state once" do
    schema =
      Jido.Joi.object(%{
        count: Jido.Joi.integer() |> Jido.Joi.refine({__MODULE__, :observe, []}) |> Jido.Joi.default(0)
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
      Jido.Joi.object(%{
        count: Jido.Joi.integer() |> Jido.Joi.refine({__MODULE__, :observe, []}),
        enabled: Jido.Joi.boolean() |> Jido.Joi.default(true)
      })

    definition =
      Agent.define!(%{
        name: "partial_initial_state",
        schema: schema,
        initial_state: %{enabled: false}
      })

    assert {:ok, agent} =
             Agent.instantiate(definition,
               id: Jido.Id.uuid7(),
               state: %{count: 3}
             )

    assert agent.state === %{count: 3, enabled: false}
    assert_received {:validated, 3}
    refute_received {:validated, _}

    invalid = %{definition | initial_state: %{enabled: "false"}}
    assert {:error, %Jido.Error.ValidationError{path: [:state]}} = Agent.instantiate(invalid, id: "bad")
  end

  @tag obligation: "jido.agent.I8"
  test "defaults and explicit nil cannot insert invalid values" do
    for schema <- [
          Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default("invalid")}),
          Jido.Joi.object(%{nested: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default("invalid")})})
        ],
        state <- [%{}, %{count: nil}, %{nested: %{}}] do
      definition = Agent.define!(%{name: "invalid_default", schema: schema})

      assert {:error, %{__exception__: true}} =
               Agent.instantiate(definition, id: Jido.Id.uuid7(), state: state)
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "initialization retains nested defaults, explicit nil, and supplied values" do
    schema =
      Jido.Joi.object(%{
        config: Jido.Joi.map() |> Jido.Joi.default(%{first: 1, second: 2}),
        count: Jido.Joi.integer() |> Jido.Joi.default(3),
        optional: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.default(nil)
      })

    definition = Agent.define!(%{name: "nested_defaults", schema: schema})

    assert {:ok, agent} =
             Agent.instantiate(definition,
               id: Jido.Id.uuid7(),
               state: %{config: %{second: 4}, count: nil}
             )

    assert agent.state == %{config: %{second: 4}, count: 3, optional: nil}

    assert {:error, %Jido.Error.ValidationError{code: :incomplete_state}} =
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
      leaf = Jido.Joi.integer() |> Jido.Joi.refine({__MODULE__, :observe, []}) |> Jido.Joi.default(1)

      nested =
        Enum.reduce(1..depth//1, leaf, fn _, child ->
          Jido.Joi.object(%{child: child}) |> Jido.Joi.default(%{})
        end)

      expected = Enum.reduce(1..depth//1, 1, fn _, child -> %{child: child} end)
      definition = Agent.define!(%{name: "deep_defaults", schema: Jido.Joi.object(%{root: nested})})
      assert {:ok, agent} = Agent.instantiate(definition, id: Jido.Id.uuid7())
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
      leaf = Jido.Joi.integer() |> Jido.Joi.default("bad")

      nested =
        Enum.reduce(1..depth//1, leaf, fn _, child ->
          Jido.Joi.object(%{child: child}) |> Jido.Joi.default(%{})
        end)

      definition =
        Agent.define!(%{name: "deep_invalid_defaults", schema: Jido.Joi.object(%{root: nested})})

      assert {:error, %Jido.Error.ValidationError{details: %{issues: [%{path: path}]}}} =
               Agent.instantiate(definition, id: Jido.Id.uuid7())

      assert path == [:root | List.duplicate(:child, depth)]
    end
  end

  @tag obligation: "jido.agent.I9"
  test "state schemas reject transforms and coercion before callbacks run" do
    for field <- [
          Jido.Joi.integer() |> Jido.Joi.transform({__MODULE__, :increment, []}),
          Jido.Joi.integer(coerce: true),
          Jido.Joi.list(Jido.Joi.integer() |> Jido.Joi.transform({__MODULE__, :increment, []})),
          Jido.Joi.union([Jido.Joi.integer(), Jido.Joi.string(coerce: true)])
        ] do
      schema = Jido.Joi.object(%{nested: Jido.Joi.object(%{value: field})})

      assert {:error, %Jido.Error.ValidationError{path: [:schema | _]}} =
               Agent.define(%{name: "invalid_schema", schema: schema})

      refute_received {:transformed, _}
    end
  end

  @tag obligation: "jido.agent.I9"
  test "input conversion types and dynamic schemas cannot bypass the state contract" do
    for field <- [Jido.Joi.string_boolean(), Jido.Joi.lazy({__MODULE__, :lazy_transform, []})] do
      assert {:error, %Jido.Error.ValidationError{path: [:schema | _]}} =
               Agent.define(%{name: "conversion_schema", schema: Jido.Joi.object(%{value: field})})

      refute_received :lazy_schema_called
    end
  end

  def lazy_transform do
    send(self(), :lazy_schema_called)
    Jido.Joi.integer() |> Jido.Joi.transform({__MODULE__, :increment, []})
  end

  @tag obligation: "jido.agent.I8"
  test "a successful refinement cannot change initialized state" do
    schema =
      Jido.Joi.object(%{
        count: Jido.Joi.integer() |> Jido.Joi.refine({__MODULE__, :mutate, []}) |> Jido.Joi.default(1)
      })

    definition = Agent.define!(%{name: "mutating_refinement", schema: schema})

    assert {:error, %{__exception__: true}} =
             Agent.instantiate(definition, id: Jido.Id.uuid7())

    assert_received {:mutated, 1}
    refute_received {:mutated, _}
  end

  @tag obligation: "jido.agent.I9"
  test "stored state checks do not fill defaults or replace explicit nil" do
    schema =
      Jido.Joi.object(%{
        nested: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(1)}) |> Jido.Joi.default(%{})
      })

    definition = Agent.define!(%{name: "stored_defaults", schema: schema})
    agent = Agent.instantiate!(definition, id: Jido.Id.uuid7())
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
    schema = Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(1) |> Jido.Joi.optional()})
    definition = Agent.define!(%{name: "optional_default", schema: schema})
    agent = Agent.instantiate!(definition, id: Jido.Id.uuid7())
    assert agent.state === %{}
    assert {:ok, ^agent} = Agent.validate(agent)
    assert {:ok, ^agent} = Agent.transition(agent, %{})

    assert {:ok, %{state: %{count: 1}}} =
             Agent.instantiate(definition, id: Jido.Id.uuid7(), state: %{count: nil})

    assert {:error, _} = Agent.transition(agent, %{count: nil})
  end

  @tag obligation: "jido.agent.I8"
  test "nil defaults need a nullable schema" do
    for nullable? <- [false, true] do
      field = if nullable?, do: Jido.Joi.integer() |> Jido.Joi.nullable(), else: Jido.Joi.integer()

      definition =
        Agent.define!(%{
          name: "nil_default",
          schema: Jido.Joi.object(%{count: Jido.Joi.default(field, nil)})
        })

      if nullable? do
        assert {:ok, %{state: %{count: nil}} = agent} =
                 Agent.instantiate(definition, id: Jido.Id.uuid7())

        assert {:ok, ^agent} = Agent.validate(agent)
      else
        assert {:error, %{__exception__: true}} =
                 Agent.instantiate(definition, id: Jido.Id.uuid7())
      end
    end
  end

  @tag obligation: "jido.agent.I9"
  test "stored checks cannot silently strip nested keys" do
    schema = Jido.Joi.object(%{nested: Jido.Joi.map(%{count: Jido.Joi.integer()})})
    definition = Agent.define!(%{name: "stored_unknown", schema: schema})

    agent =
      Agent.instantiate!(definition,
        id: Jido.Id.uuid7(),
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
         Jido.Joi.integer() |> Jido.Joi.transform({Jido.Agent.StateTest, :increment, []}) |> Jido.Joi.default(1)}
  end

  @tag obligation: "jido.agent.I10"
  test "composed Plugin state follows the same schema policy" do
    assert {:error, %Jido.Error.ValidationError{path: [:schema | _]}} =
             Agent.define(%{
               name: "plugin_transform",
               plugins: [
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
