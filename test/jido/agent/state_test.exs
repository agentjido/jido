defmodule Jido.Agent.StateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  def observe(value, _opts) do
    send(self(), {:validated, value})
    :ok
  end

  test "initialization validates unchanged state once" do
    schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}) |> Zoi.default(0)
      })

    definition = Agent.new!(name: "single_validation", schema: schema)

    for overrides <- [[], [state: %{count: 4}]] do
      assert {:ok, agent} = Agent.instantiate(definition, overrides)
      assert_received {:validated, value}
      assert value == agent.state.count
      refute_received {:validated, _}
    end
  end

  test "defaults and explicit nil cannot insert invalid values" do
    for schema <- [
          Zoi.object(%{count: Zoi.integer() |> Zoi.default("invalid")}),
          Zoi.object(%{nested: Zoi.object(%{count: Zoi.integer() |> Zoi.default("invalid")})})
        ],
        state <- [%{}, %{count: nil}, %{nested: %{}}] do
      definition = Agent.new!(name: "invalid_default", schema: schema)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(definition, state: state)
    end
  end

  test "initialization retains nested defaults, explicit nil, and supplied values" do
    schema =
      Zoi.object(%{
        config: Zoi.map() |> Zoi.default(%{first: 1, second: 2}),
        count: Zoi.integer() |> Zoi.default(3),
        optional: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
      })

    definition = Agent.new!(name: "nested_defaults", schema: schema)

    assert {:ok, agent} =
             Agent.instantiate(definition, state: %{config: %{second: 4}, count: nil})

    assert agent.state == %{config: %{first: 1, second: 4}, count: 3, optional: nil}

    assert {:error, %Jido.Error.ValidationError{details: %{missing_keys: [:config, :count]}}} =
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

  test "nested defaults reach the leaf and validate it once" do
    for depth <- [0, 1, 2, 64, 70] do
      leaf = Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}) |> Zoi.default(1)

      nested =
        Enum.reduce(1..depth//1, leaf, fn _, child ->
          Zoi.object(%{child: child}) |> Zoi.default(%{})
        end)

      expected = Enum.reduce(1..depth//1, 1, fn _, child -> %{child: child} end)
      definition = Agent.new!(name: "deep_defaults", schema: Zoi.object(%{root: nested}))
      assert {:ok, agent} = Agent.instantiate(definition)
      assert agent.state === %{root: expected}
      assert_received {:validated, 1}
      refute_received {:validated, _}
      assert {:ok, ^agent} = Agent.validate_instance(agent)
      assert_received {:validated, 1}
      refute_received {:validated, _}
    end
  end

  test "deep invalid defaults fail during initialization" do
    for depth <- [0, 1, 2, 64, 70] do
      leaf = Zoi.integer() |> Zoi.default("bad")

      nested =
        Enum.reduce(1..depth//1, leaf, fn _, child ->
          Zoi.object(%{child: child}) |> Zoi.default(%{})
        end)

      definition = Agent.new!(name: "deep_invalid_defaults", schema: Zoi.object(%{root: nested}))

      assert {:error, %Jido.Error.ValidationError{details: %{errors: [%Zoi.Error{path: path}]}}} =
               Agent.instantiate(definition)

      assert path == [:root | List.duplicate(:child, depth)]
    end
  end

  test "state schemas reject transforms and coercion before callbacks run" do
    for field <- [
          Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []}),
          Zoi.integer(coerce: true),
          Zoi.list(Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []})),
          Zoi.union([Zoi.integer(), Zoi.string(coerce: true)])
        ] do
      schema = Zoi.object(%{nested: Zoi.object(%{value: field})})

      assert {:error, %Jido.Error.ValidationError{subject: :schema}} =
               Agent.new(name: "invalid_schema", schema: schema)

      refute_received {:transformed, _}
    end
  end

  test "input conversion types and dynamic schemas cannot bypass the state contract" do
    for field <- [Zoi.string_boolean(), Zoi.lazy({__MODULE__, :lazy_transform, []})] do
      assert {:error, %Jido.Error.ValidationError{subject: :schema}} =
               Agent.new(name: "conversion_schema", schema: Zoi.object(%{value: field}))

      refute_received :lazy_schema_called
    end
  end

  def lazy_transform do
    send(self(), :lazy_schema_called)
    Zoi.integer() |> Zoi.transform({__MODULE__, :increment, []})
  end

  test "a successful refinement cannot change initialized state" do
    schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.refine({__MODULE__, :mutate, []}) |> Zoi.default(1)
      })

    definition = Agent.new!(name: "mutating_refinement", schema: schema)
    assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(definition)
    assert_received {:mutated, 1}
    refute_received {:mutated, _}
  end

  test "stored state checks do not fill defaults or replace explicit nil" do
    schema =
      Zoi.object(%{
        nested: Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)}) |> Zoi.default(%{})
      })

    definition = Agent.new!(name: "stored_defaults", schema: schema)
    agent = Agent.instantiate!(definition)
    assert agent.state === %{nested: %{count: 1}}

    for state <- [%{}, %{nested: %{}}, %{nested: nil}, %{nested: %{count: nil}}] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.validate_instance(%{agent | state: state})

      assert {:error, %Jido.Error.ValidationError{}} = Agent.transition(agent, state)
      assert agent.state === %{nested: %{count: 1}}
    end
  end

  test "optional defaulted fields stay absent in input and stored state" do
    schema = Zoi.object(%{count: Zoi.integer() |> Zoi.default(1) |> Zoi.optional()})
    definition = Agent.new!(name: "optional_default", schema: schema)
    agent = Agent.instantiate!(definition)
    assert agent.state === %{}
    assert {:ok, ^agent} = Agent.validate_instance(agent)
    assert {:ok, ^agent} = Agent.transition(agent, %{})
    assert {:ok, %{state: %{count: 1}}} = Agent.instantiate(definition, state: %{count: nil})
    assert {:error, _} = Agent.transition(agent, %{count: nil})
  end

  test "nil defaults need a nullable schema" do
    for nullable? <- [false, true] do
      field = if nullable?, do: Zoi.integer() |> Zoi.nullable(), else: Zoi.integer()

      definition =
        Agent.new!(name: "nil_default", schema: Zoi.object(%{count: Zoi.default(field, nil)}))

      if nullable? do
        assert {:ok, %{state: %{count: nil}} = agent} = Agent.instantiate(definition)
        assert {:ok, ^agent} = Agent.validate_instance(agent)
      else
        assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(definition)
      end
    end
  end

  test "stored checks cannot silently strip nested keys" do
    schema = Zoi.object(%{nested: Zoi.map(%{count: Zoi.integer()})})
    definition = Agent.new!(name: "stored_unknown", schema: schema)
    agent = Agent.instantiate!(definition, state: %{nested: %{count: 1}})
    assert {:error, _} = Agent.transition(agent, %{nested: %{count: 1, other: 2}})
    assert {:ok, ^agent} = Agent.validate_instance(agent)
  end

  defmodule TransformPlugin do
    use Jido.Plugin
    @impl true
    def state_spec(_opts),
      do:
        {:plugin_count,
         Zoi.integer() |> Zoi.transform({Jido.Agent.StateTest, :increment, []}) |> Zoi.default(1)}
  end

  test "composed Plugin state follows the same schema policy" do
    assert {:error, %Jido.Error.ValidationError{subject: :schema}} =
             Agent.new(name: "plugin_transform", plugins: [TransformPlugin])

    refute_received {:transformed, _}
  end

  test "checkpoint restore rejects missing defaults and preserves nullable nil" do
    schema =
      Zoi.object(%{
        nested:
          Zoi.object(%{count: Zoi.integer() |> Zoi.nullable() |> Zoi.default(3)})
          |> Zoi.default(%{})
      })

    agent = Agent.new!(name: "restore_defaults", schema: schema) |> Agent.instantiate!()
    assert {:ok, stored_nil} = Agent.transition(agent, %{nested: %{count: nil}})
    assert {:ok, checkpoint} = Agent.checkpoint(stored_nil)
    assert {:ok, ^stored_nil} = Agent.restore(Agent, checkpoint)

    for state <- [%{}, %{nested: %{}}] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.restore(Agent, %{checkpoint | state: state})
    end
  end

  test "input empty values do not remove stored nullable nil" do
    schema =
      Zoi.object(%{count: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil)},
        empty_values: [nil]
      )

    agent = Agent.new!(name: "empty_nil", schema: schema) |> Agent.instantiate!()
    assert agent.state === %{count: nil}
    assert Agent.validate_instance(agent) === {:ok, agent}
    assert Agent.transition(agent, agent.state) === {:ok, agent}
    assert {:ok, checkpoint} = Agent.checkpoint(agent)
    assert {:ok, ^agent} = Agent.restore(Agent, checkpoint)
  end
end
