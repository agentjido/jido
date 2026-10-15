defmodule JidoTest.Contract.AgentDefinitionTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent
  alias Jido.Error.ValidationError
  alias JidoTest.AgentContract, as: F

  @tag obligation: ["jido.agent.I1", "jido.agent.I5"]
  test "all supported declarations give the same complete neutral value" do
    F.with_agent(
      """
      agent do
        schema F.schema()
        metadata %{items: [1, 1.0, false, nil, {:tag, <<255>>}]}
        plugin F.First, config: %{initial: 2}
        plugin F.Second
      end
      routes do
        signal_source "/contract"
        route "test.run", F.Return, as: :run, defaults: %{flag: false}, priority: 7
        route "test.flow", F.Flow, priority: -3
      end
      """,
      fn module ->
        from_module = module.definition()

        expected =
          F.definition(
            module: module,
            vsn: 4,
            plugins: [{F.First, [initial: 2]}, {F.Second, []}],
            metadata: %{items: [1, 1.0, false, nil, {:tag, <<255>>}]},
            routes: [
              {"test.run", {F.Return, %{flag: false}}, priority: 7},
              {"test.flow", F.Flow, priority: -3}
            ]
          )

        assert from_module === expected
        assert {:ok, ^expected} = Agent.new(Map.from_struct(expected))
        assert {:ok, ^expected} = Agent.new(Map.to_list(Map.from_struct(expected)))
        assert {:ok, document, registry} = Agent.Codec.encode(expected)

        assert {:ok, ^expected} =
                 Agent.Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

        assert {:ok, ^expected} = Agent.new(expected)
        assert Agent.definition?(expected)
        refute Agent.instance?(expected)
      end,
      ", vsn: 4"
    )
  end

  @tag obligation: "jido.agent.I2"
  test "definitions reject every partial or complete instance form" do
    definition = F.definition()
    assert definition.id == nil
    assert definition.state == nil

    for attrs <- [%{id: "id"}, %{state: %{}}, %{id: "id", state: %{}}] do
      assert {:error, %ValidationError{}} = Agent.new(Map.merge(%{name: "contract"}, attrs))
      invalid = struct(definition, attrs)
      assert {:error, %ValidationError{}} = Agent.new(invalid)
      assert {:error, %ValidationError{}} = Agent.validate_definition(invalid)
      refute Agent.definition?(invalid)
    end

    instance = Agent.instantiate!(definition)
    assert Agent.definition(instance) === definition
    assert {:ok, ^definition} = Agent.validate(definition)
    assert {:ok, ^instance} = Agent.validate(instance)
    refute Agent.instance?(%{instance | id: ""})

    for value <- [nil, 7, %{}, []],
        do: assert({:error, %ValidationError{}} = Agent.validate(value))
  end

  @tag obligation: "jido.agent.I3"
  test "constructors reject invalid fields and preserve error paths" do
    for {key, values} <- [
          name: [nil, "", 1, :name],
          description: [1, false, %{}],
          vsn: [0, -1, 1.0, "1", false],
          metadata: [nil, [], %URI{}],
          module: [nil, "Elixir.Missing", Enum, JidoTest.MissingAgent],
          schema: [nil, Zoi.integer(), Zoi.map()],
          plugins: [:invalid, [Enum], [{F.First, :invalid}]],
          routes: [
            :invalid,
            [{"test.run", Enum}],
            [{"test.run", [F.Add]}],
            [{"test.run", {F.Add, nil}}]
          ]
        ],
        value <- values do
      assert {:error, %ValidationError{}} = Agent.new(Keyword.put([name: "valid"], key, value))
    end

    assert {:error, %ValidationError{details: %{key: :unknown}}} =
             Agent.new(name: "valid", unknown: 1)

    for value <- [nil, :invalid, [1 | :tail], [name: "valid"] ++ [:invalid], %URI{}] do
      assert {:error, %ValidationError{}} = Agent.new(value)
    end

    assert {:ok, %{vsn: nil, module: Agent}} = Agent.new(name: "valid")
    assert {:ok, %{description: "", vsn: 1}} = Agent.new(name: "valid", description: "", vsn: 1)
  end

  @tag obligation: "jido.agent.I3"
  test "state schemas reject transforms, coercion, lazy input, and non-static defaults" do
    for schema <- [
          Zoi.object(%{value: Zoi.integer(coerce: true)}),
          Zoi.object(%{value: Zoi.string() |> Zoi.transform(&String.upcase/1)}),
          Zoi.object(%{value: Zoi.lazy(fn -> Zoi.integer() end)}),
          Zoi.object(%{value: Zoi.any() |> Zoi.default(self())})
        ] do
      assert {:error, %ValidationError{}} = Agent.new(name: "invalid_schema", schema: schema)
    end
  end

  @tag obligation: ["jido.agent.I4", "jido.agent.I7", "jido.agent.I11"]
  test "data keyword boundaries keep the last duplicate" do
    assert {:ok, %{name: "last"} = definition} =
             Agent.new(name: "first", name: "last", schema: F.schema())

    assert {:ok, %{id: "last"} = instance} =
             Agent.instantiate(definition, id: "first", id: "last")

    assert {:ok, %{state: %{count: 2}}} = Agent.set(instance, count: 1, count: 2)
  end

  @tag obligation: ["jido.agent.I5", "jido.agent.I7", "jido.agent.I8"]
  test "independent instances preserve the neutral definition and explicit values" do
    definition = F.definition(plugins: [{F.First, [initial: 5]}])
    first = Agent.instantiate!(definition, state: %{count: 0, enabled: false, note: nil})
    second = Agent.instantiate!(definition)
    assert first.id != second.id
    assert is_binary(first.id) and byte_size(first.id) > 0
    assert is_binary(second.id) and byte_size(second.id) > 0

    assert first.state === %{
             count: 0,
             enabled: false,
             note: "default",
             settings: %{a: 1, b: 2},
             first: 5
           }

    assert second.state === %{
             count: 0,
             enabled: true,
             note: "default",
             settings: %{a: 1, b: 2},
             first: 5
           }

    assert Agent.definition(first) === definition
    assert Agent.definition(second) === definition
    assert definition.id == nil and definition.state == nil
    assert {:ok, %{state: %{note: nil}}} = Agent.set(first, note: nil)

    nil_definition =
      Agent.new!(
        name: "nil",
        schema: Zoi.object(%{note: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)})
      )

    assert Agent.instantiate!(nil_definition, state: %{note: nil}).state === %{note: nil}
    assert Agent.instance?(first)
    refute Agent.definition?(first)
  end

  @tag obligation: "jido.agent.I7"
  test "instance overrides have a strict boundary" do
    definition = F.definition()

    for attrs <- [
          [name: "other"],
          %{routes: []},
          [state: nil],
          [state: []],
          [state: %URI{}],
          [state: %{count: "1"}],
          [state: %{extra: 1}],
          [id: ""],
          [id: 1],
          [:invalid],
          [1 | :tail],
          :invalid
        ] do
      assert {:error, %ValidationError{}} = Agent.instantiate(definition, attrs)
    end

    assert {:error, %ValidationError{}} = Agent.instantiate(F.instance(), [])
    assert {:error, %ValidationError{}} = Agent.instantiate(:not_an_agent, [])
    assert {:error, %ValidationError{}} = Agent.instantiate(%{}, [])
    assert {:ok, %{id: "supplied"}} = Agent.instantiate(definition, %{id: "supplied"})
  end

  @tag obligation: "jido.agent.I9"
  test "stored validation returns exact values and never converts or supplies required fields" do
    original = F.instance()
    assert {:ok, ^original} = Agent.validate_instance(original)

    for state <- [
          nil,
          [],
          %URI{},
          Map.delete(original.state, :count),
          %{original.state | count: "1"},
          Map.put(original.state, :extra, 1)
        ] do
      assert {:error, %ValidationError{}} = Agent.validate_instance(%{original | state: state})
    end

    assert {:error, %ValidationError{}} = Agent.validate_instance(original |> Map.put(:id, nil))
    assert {:error, %ValidationError{}} = Agent.validate_instance(F.definition())
    assert {:error, %ValidationError{}} = Agent.validate_instance(nil)
  end

  @tag obligation: ["jido.agent.I10", "jido.agent.I18"]
  test "one schema composes domain and Plugin state and rejects ownership conflicts" do
    definition = F.definition(plugins: [F.First, F.Second, F.Stateless, F.PreparedOnly])
    instance = Agent.instantiate!(definition, state: %{first: 4})

    assert instance.state == %{
             count: 0,
             enabled: true,
             note: "default",
             settings: %{a: 1, b: 2},
             first: 4,
             second: 0
           }

    assert {:ok, schema} = Agent.complete_schema(definition)
    assert {:ok, state} = Zoi.parse(schema, %{})
    assert state == %{instance.state | first: 0}
    assert Agent.complete_schema!(definition) === schema

    for plugins <- [
          [{F.First, [key: :count]}],
          [{F.First, [key: :owned]}, {F.Second, [key: :owned]}],
          [F.First, F.First]
        ] do
      assert {:error, %ValidationError{}} =
               Agent.new(name: "conflict", schema: F.schema(), plugins: plugins)
    end

    assert {:error, %ValidationError{}} =
             Agent.validate_instance(%{instance | state: Map.delete(instance.state, :first)})
  end

  @tag obligation: "jido.agent.I11"
  test "set shallowly replaces domain fields and validates the full state" do
    source = F.instance(plugins: [F.First])
    assert {:ok, candidate} = Agent.set(source, %{settings: %{a: 9}, count: 7})
    assert candidate.state === %{source.state | count: 7, settings: %{a: 9}}
    assert candidate.id == source.id
    assert Agent.definition(candidate) === Agent.definition(source)
    assert source.state.count == 0
    assert source.state.settings == %{a: 1, b: 2}

    for attrs <- [%{first: 2}, %{unknown: 1}, %{count: "1"}, nil, [:invalid], %URI{}] do
      assert {:error, %ValidationError{}} = Agent.set(source, attrs)
    end

    assert {:error, %ValidationError{message: "Agent domain schema must be a Zoi object"}} =
             Agent.set(%{source | schema: nil}, %{})

    assert {:error, %ValidationError{}} = Agent.set(F.definition(), %{})

    assert {:error, %ValidationError{}} =
             Agent.set(%{source | state: Map.delete(source.state, :count)}, %{})
  end

  @tag obligation: "jido.agent.I24"
  test "bang boundaries raise the same errors returned by tuple boundaries" do
    assert_same_error(fn -> Agent.new(name: 2) end, fn -> Agent.new!(name: 2) end)

    assert_same_error(fn -> Agent.instantiate(F.definition(), id: "") end, fn ->
      Agent.instantiate!(F.definition(), id: "")
    end)

    invalid = %{F.definition() | schema: nil}

    assert_same_error(fn -> Agent.complete_schema(invalid) end, fn ->
      Agent.complete_schema!(invalid)
    end)

    assert Agent.new!(name: "valid") == elem(Agent.new(name: "valid"), 1)

    assert Agent.instantiate!(F.definition(), id: "fixed") ==
             elem(Agent.instantiate(F.definition(), id: "fixed"), 1)
  end

  @tag obligation: "jido.agent.I25"
  test "required top-level public functions and Turn constructors remain available" do
    required = [
      new: 1,
      new!: 1,
      instantiate: 1,
      instantiate: 2,
      instantiate!: 1,
      instantiate!: 2,
      validate: 1,
      validate_definition: 1,
      validate_instance: 1,
      definition?: 1,
      instance?: 1,
      definition: 1,
      complete_schema: 1,
      complete_schema!: 1,
      set: 2,
      cmd: 2,
      cmd: 3,
      handle_signal: 2
    ]

    for {name, arity} <- required, do: assert(function_exported?(Agent, name, arity))

    for {name, arity} <- [
          schema: 0,
          new: 1,
          new: 2,
          new: 3,
          new!: 1,
          new!: 2,
          new!: 3,
          validate: 1
        ],
        do: assert(function_exported?(Agent.Turn, name, arity))

    assert Agent.__info__(:macros) |> Enum.member?({:__using__, 1})
    assert %Zoi.Types.Struct{} = Agent.Turn.schema()
    assert {:ok, turn} = Agent.Turn.new(F.Return)
    assert Agent.Turn.new!(F.Return) == turn
    source = F.signal()
    assert {:ok, bound} = Agent.Turn.new(F.Return, nil, source)
    assert Agent.Turn.new!(F.Return, nil, source) == bound
    assert {:ok, ^bound} = Agent.Turn.validate(bound)
    assert_same_error(fn -> Agent.Turn.new(Enum) end, fn -> Agent.Turn.new!(Enum) end)

    assert_same_error(fn -> Agent.Turn.new(Enum, %{}, source) end, fn ->
      Agent.Turn.new!(Enum, %{}, source)
    end)

    assert {:error, %ValidationError{}} = Agent.Turn.validate(nil)
  end

  @tag obligation: ["jido.agent.I1", "jido.agent.I2", "jido.agent.I5"]
  test "a neutral Agent struct has the same complete fields as data construction" do
    definition = F.definition()
    authored = struct!(Agent, Map.from_struct(definition))
    assert {:ok, ^definition} = Agent.new(authored)
    assert authored === definition
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I5", "jido.agent.I12", "jido.agent.I13"]
  test "map, tuple, and Router route declarations keep every supported option" do
    defaults = %{flag: false, nested: %{a: 1}}

    expected =
      F.definition(routes: [{"test.run", {F.Return, defaults}, priority: 7, match: &F.match?/1}])

    for route <- [
          %{
            path: "test.run",
            target: F.Return,
            defaults: defaults,
            priority: 7,
            match: &F.match?/1
          },
          %Jido.Signal.Router.Route{
            path: "test.run",
            target: {F.Return, defaults},
            priority: 7,
            match: &F.match?/1
          },
          {"test.run", F.Return, defaults: defaults, priority: 7, match: &F.match?/1}
        ] do
      assert F.definition(routes: [route]) === expected
    end

    for routes <- [
          [[]],
          [[{"test.run", F.Return}]],
          [{"test.run", F.Return, [unknown: 1]}],
          [{"test.run", F.Return, [defaults: %URI{}]}],
          [{"test.run", {F.Return, %URI{}}}],
          [%{path: "test.run", target: F.Return, extra: 1}],
          [{"test.run", F.Return} | :tail]
        ] do
      assert {:error, %{__exception__: true}} = Agent.new(name: "invalid", routes: routes)
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I23"]
  test "invalid declaration paths identify the field and route or Plugin index" do
    assert {:error, %{details: %{source_path: [:routes, 1, :target]}}} =
             Agent.new(
               name: "invalid",
               routes: [{"test.valid", F.Return}, {"test.invalid", Enum}]
             )

    assert {:error, %{details: %{source_path: [:plugins, 1]}}} =
             Agent.new(name: "invalid", plugins: [F.First, Enum])

    assert {:error, %{details: %{source_path: [:description]}}} =
             Agent.new(name: "invalid", description: 5)
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "nested initialization defaults do not become stored-state repair" do
    schema =
      Zoi.object(%{
        nested:
          Zoi.object(%{
            count: Zoi.integer() |> Zoi.default(3),
            enabled: Zoi.boolean() |> Zoi.default(true)
          })
          |> Zoi.default(%{}),
        optional: Zoi.string() |> Zoi.optional()
      })

    definition = Agent.new!(name: "nested", schema: schema)
    source = Agent.instantiate!(definition, state: %{nested: %{count: 0, enabled: false}})
    assert source.state === %{nested: %{count: 0, enabled: false}}
    assert Agent.instantiate!(definition).state === %{nested: %{count: 3, enabled: true}}
    assert {:ok, ^source} = Agent.validate_instance(source)

    assert {:error, %ValidationError{}} =
             Agent.validate_instance(%{source | state: %{nested: %{}}})
  end

  @tag obligation: "jido.agent.I23"
  test "built-in validation faults have nonempty messages without fixed wording" do
    for result <- [
          Agent.new(nil),
          Agent.new(name: "ok", unknown: true),
          Agent.new(name: "ok", id: "half"),
          Agent.new(name: nil),
          Agent.new(name: "ok", description: 1),
          Agent.new(name: "ok", vsn: 0),
          Agent.new(name: "ok", module: nil),
          Agent.new(name: "ok", module: Enum),
          Agent.new(name: "ok", module: JidoTest.MissingAgent),
          Agent.new(name: "ok", metadata: []),
          Agent.new(name: "ok", routes: nil),
          Agent.new(name: "ok", routes: [{"test.run", F.Return} | :tail]),
          Agent.new(name: "ok", schema: nil),
          Agent.new(name: "ok", plugins: [Enum]),
          Agent.new(name: "ok", routes: [{"run", Enum}]),
          Agent.instantiate(nil),
          Agent.instantiate(%{}),
          Agent.instantiate(F.Selection),
          Agent.instantiate(JidoTest.MissingAgent),
          Agent.complete_schema(%{F.definition() | schema: nil}),
          Agent.new(name: "bad", schema: Zoi.object(%{v: Zoi.string_boolean()})),
          Agent.new(name: "bad", schema: Zoi.object(%{v: Zoi.any() |> Zoi.default(self())})),
          Agent.validate_instance(%{F.instance() | state: nil}),
          Agent.instantiate(F.definition(), state: nil),
          Agent.instantiate(F.definition(), id: ""),
          Agent.instantiate(F.definition(), name: "other"),
          Agent.instantiate(F.definition(), [:invalid]),
          Agent.instantiate(F.definition(), state: %{count: "bad"}),
          Agent.new(F.instance()),
          Agent.validate(nil),
          Agent.validate(%{F.definition() | id: "half"}),
          Agent.validate_definition(nil),
          Agent.validate_instance(nil),
          Agent.set(F.definition(), %{}),
          Agent.set(F.instance(), nil),
          Agent.set(F.instance(), extra: 1),
          Agent.cmd(F.instance(), F.signal(), nil),
          Agent.cmd(F.instance(), F.signal(), [:invalid]),
          Agent.Turn.new(F.Return, :invalid),
          Agent.Turn.validate(nil)
        ] do
      assert {:error, %{__exception__: true, message: message}} = result
      assert is_binary(message) and byte_size(message) > 0
    end
  end

  defp assert_same_error(tuple, bang) do
    assert {:error, error} = tuple.()
    raised = assert_raise error.__struct__, bang

    assert Map.drop(Map.from_struct(raised), [:stacktrace]) ===
             Map.drop(Map.from_struct(error), [:stacktrace])
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I23"]
  test "normalization errors identify each route position" do
    for bad <- [
          [],
          [path: "test.bad", target: F.Return],
          %{path: "test.bad", target: F.Return, unknown: 1},
          {"test.bad", F.Return, defaults: %URI{}}
        ] do
      assert {:error, %ValidationError{details: %{source_path: [:routes, 1]}} = error} =
               Agent.new(name: "contract", routes: [{"test.run", F.Return}, bad])

      assert is_binary(error.message) and byte_size(error.message) > 0
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I5"]
  test "route maps and option tuples retain the default priority" do
    for route <- [%{path: "test.run", target: F.Return}, {"test.run", F.Return, []}] do
      assert [%{priority: 0, match: nil, path: "test.run", target: F.Return}] =
               F.definition(routes: [route]).routes
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9", "jido.agent.I11"]
  test "initialization merges required map defaults and preserves optional absence" do
    schema =
      Zoi.object(%{
        required: Zoi.map() |> Zoi.default(%{a: 1, b: 2}) |> Zoi.required(),
        optional: Zoi.string() |> Zoi.default("default") |> Zoi.optional()
      })

    definition = F.definition(schema: schema)
    source = Agent.instantiate!(definition, state: %{required: %{a: 9}})
    assert source.state === %{required: %{a: 9, b: 2}}
    assert Agent.instantiate!(definition, state: %{optional: nil}).state.optional == "default"
    assert {:ok, ^source} = Agent.validate_instance(source)
    assert {:ok, ^source, []} = Agent.cmd(source, F.signal())
    assert {:ok, %{state: %{required: %{a: 9}}}} = Agent.set(source, required: %{a: 9})

    for field <- [
          Zoi.integer() |> Zoi.default("wrong"),
          Zoi.integer() |> Zoi.min(1) |> Zoi.default(0)
        ] do
      result =
        with {:ok, definition} <-
               Agent.new(name: "invalid_default", schema: Zoi.object(%{value: field})) do
          Agent.instantiate(definition, state: %{value: nil})
        end

      assert {:error, %ValidationError{}} = result
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I9"]
  test "static schema validation rejects nested input conversion and MFA transforms" do
    for schema <- [
          Zoi.object(%{value: Zoi.string_boolean()}),
          Zoi.object(%{value: Zoi.array(Zoi.integer(coerce: true))}),
          Zoi.object(%{value: Zoi.map_set(Zoi.integer(coerce: true))}),
          Zoi.object(%{value: Zoi.integer(coerce: true) |> Zoi.nullable()}),
          Zoi.object(%{value: Zoi.lazy({F, :schema, []})}),
          Zoi.object(%{value: Zoi.string() |> Zoi.transform({String, :upcase, []})}),
          Zoi.object(%{value: Zoi.union([Zoi.integer(coerce: true), Zoi.string()])}),
          Zoi.object(%{value: Zoi.map(Zoi.integer(coerce: true), Zoi.string())}),
          Zoi.object(%{value: Zoi.map(Zoi.string(), Zoi.integer(coerce: true))})
        ] do
      assert {:error, %ValidationError{}} = Agent.new(name: "validation_only", schema: schema)
    end
  end

  @tag obligation: ["jido.agent.I8", "jido.agent.I9"]
  test "a static refinement cannot change a value during initialization" do
    schema = Zoi.object(%{value: Zoi.integer() |> Zoi.refine({F, :changed_refinement, []})})
    definition = Agent.new!(name: "immutable_refinement", schema: schema)
    assert {:error, %ValidationError{}} = Agent.instantiate(definition, state: %{value: 1})
  end

  @tag obligation: ["jido.agent.I14", "jido.agent.I23", "jido.agent.I25"]
  test "Turn constructors retain exact input until selection normalizes it" do
    signal = F.signal()

    for input <- [%{amount: 2}, [amount: 1, amount: 2], nil] do
      assert {:ok, %Agent.Turn{executable: F.Return, input: ^input, source_signal: nil}} =
               Agent.Turn.new(F.Return, input)

      assert {:ok, %Agent.Turn{executable: F.Return, input: ^input, source_signal: ^signal}} =
               Agent.Turn.new(F.Return, input, signal)

      assert %Agent.Turn{input: ^input} = Agent.Turn.new!(F.Return, input, signal)
    end

    assert {:error, error} = Agent.Turn.new(F.Return, %{}, %{signal | id: nil})
    assert is_binary(error.message) and byte_size(error.message) > 0
  end

  @tag obligation: "jido.agent.I3"
  test "a valid definition constructor returns without recursive normalization" do
    task = Task.async(fn -> Agent.new(name: "bounded_constructor") end)
    # Keep a recursive mutation from turning this check into a test timeout.
    result = Task.yield(task, 1_000) || Task.shutdown(task, :brutal_kill)
    assert {:ok, {:ok, %Agent{name: "bounded_constructor", id: nil, state: nil}}} = result
  end
end
