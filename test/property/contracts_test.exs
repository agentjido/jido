Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)

defmodule JidoTest.Property.ContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Codec, Directive, Turn}
  alias Jido.Codec.Registry
  alias Jido.Error
  alias Jido.Signal
  alias JidoTest.Property.Fuzz

  defmodule First do
    use Jido.Action, name: "property_contract_first"

    def run(%{delta: delta}, %{agent_state: state}),
      do: {:ok, %{value: state.value + delta, selected: 1}}
  end

  defmodule Second do
    use Jido.Action, name: "property_contract_second"

    def run(%{delta: delta}, %{agent_state: state}),
      do: {:ok, %{value: state.value + delta, selected: 2}}
  end

  defmodule RoutedFlow do
    use Jido.Flow, name: "property_contract_flow"

    flow do
      step "second", action: Second, params: input()
      output result("second")
    end
  end

  defmodule CustomSelector do
    @behaviour Agent
    def handle_signal(%Signal{data: %{delta: delta}}, _agent),
      do: Turn.new(First, %{delta: delta})
  end

  defmodule WrongSource do
    @behaviour Agent
    def handle_signal(%Signal{} = signal, _agent),
      do: Turn.new(First, %{delta: 1}, %{signal | source: "/replacement"})
  end

  defmodule Candidate do
    use Jido.Action, name: "property_contract_candidate"

    def run(%{mode: mode, value: value, effects: effects}, _context) do
      state = %{value: value, selected: 0}
      directives = Enum.map(effects, &Directive.stop/1)

      case mode do
        "valid" -> {:ok, state, directives}
        "invalid_state" -> {:ok, %{state | value: "invalid"}, directives}
        "partial" -> {:ok, %{value: value}, directives}
        "struct_state" -> {:ok, %URI{}, directives}
        "bad_middle" -> {:ok, state, [Directive.stop(:first), %URI{}, Directive.stop(:last)]}
        "bad_tail" -> {:ok, state, directives ++ [:invalid]}
        "non_list" -> {:ok, state, %{invalid: true}}
        "failure" -> {:error, Error.execution_error("property candidate rejected")}
      end
    end
  end

  @definition_modes ~w(definition instance ignored_live_state incomplete_id incomplete_state unknown_key)
  @selection_modes ~w(exact wildcard flow custom wrong_source missing invalid_type invalid_envelope bad_data nil_data keyword_data)
  @candidate_modes ~w(valid invalid_state partial struct_state bad_middle bad_tail non_list failure)
  @error_types ~w(validation execution routing timeout compensation internal)
  @error_shapes ~w(atom_key string_key keyword mixed tuple improper deep wide invalid_binary)

  for {suite, runs, time} <- [{:property, 30, 10_000}, {:fuzz, 300, 120_000}] do
    @tag [
      {suite, true},
      {:fuzz_id, "agent_definitions"},
      {:contracts, ["AGT-001"]},
      {:contract_cases, Enum.map(@definition_modes, &("AGT-001/" <> &1))},
      {:timeout, 180_000}
    ]
    test "#{suite} neutral definitions and static Codec data" do
      generator =
        StreamData.fixed_map(%{
          "mode" => StreamData.member_of(@definition_modes),
          "count" => StreamData.integer(-100..100),
          "enabled" => StreamData.boolean(),
          "label" => StreamData.string(:alphanumeric, max_length: 12)
        })

      examples =
        for mode <- @definition_modes,
            do: %{"mode" => mode, "count" => 0, "enabled" => false, "label" => "boundary"}

      run_check(
        "agent_definitions",
        generator,
        unquote(suite),
        unquote(runs),
        unquote(time),
        ["AGT-001"],
        Enum.map(@definition_modes, &("AGT-001/" <> &1)),
        examples,
        &definition_case/1
      )
    end

    @tag [
      {suite, true},
      {:fuzz_id, "turn_selection"},
      {:contracts, ["TURN-001"]},
      {:contract_cases, Enum.map(@selection_modes, &("TURN-001/" <> &1))},
      {:timeout, 180_000}
    ]
    test "#{suite} one selected Action or Flow with immutable history" do
      generator =
        StreamData.fixed_map(%{
          "mode" => StreamData.member_of(@selection_modes),
          "base" => StreamData.integer(-100..100),
          "deltas" => StreamData.list_of(StreamData.integer(-5..5), min_length: 1, max_length: 5)
        })

      examples =
        for mode <- @selection_modes, do: %{"mode" => mode, "base" => 7, "deltas" => [0, 1, -1]}

      run_check(
        "turn_selection",
        generator,
        unquote(suite),
        unquote(runs),
        unquote(time),
        ["TURN-001"],
        Enum.map(@selection_modes, &("TURN-001/" <> &1)),
        examples,
        &selection_case/1
      )
    end

    @tag [
      {suite, true},
      {:fuzz_id, "turn_validation"},
      {:contracts, ["TURN-002"]},
      {:contract_cases, Enum.map(@candidate_modes, &("TURN-002/" <> &1))},
      {:timeout, 180_000}
    ]
    test "#{suite} complete candidate and complete Directive batch" do
      generator =
        StreamData.fixed_map(%{
          "mode" => StreamData.member_of(@candidate_modes),
          "value" => StreamData.integer(-100..100),
          "effects" => StreamData.list_of(StreamData.integer(-5..5), max_length: 5),
          "flow" => StreamData.boolean()
        })

      examples =
        for mode <- @candidate_modes,
            flow <- [false, true],
            do: %{"mode" => mode, "value" => 0, "effects" => [1, 2], "flow" => flow}

      run_check(
        "turn_validation",
        generator,
        unquote(suite),
        unquote(runs),
        unquote(time),
        ["TURN-002"],
        Enum.map(@candidate_modes, &("TURN-002/" <> &1)),
        examples,
        &candidate_case/1
      )
    end

    @tag [
      {suite, true},
      {:fuzz_id, "error_outputs"},
      {:contracts, ["ERROR-001"]},
      {:contract_cases,
       Enum.map(@error_shapes, &("ERROR-001/" <> &1)) ++
         ["ERROR-001/retry_defaults", "ERROR-001/retry_override"]},
      {:timeout, 180_000}
    ]
    test "#{suite} structured error projection and retry model" do
      generator =
        StreamData.fixed_map(%{
          "type" => StreamData.member_of(@error_types),
          "shape" => StreamData.member_of(@error_shapes),
          "suffix" => StreamData.integer(0..100_000),
          "override" => StreamData.member_of([nil, true, false])
        })

      examples =
        for shape <- @error_shapes,
            type <- @error_types,
            do: %{"type" => type, "shape" => shape, "suffix" => 0, "override" => nil}

      examples =
        examples ++
          [
            %{"type" => "validation", "shape" => "mixed", "suffix" => 1, "override" => true},
            %{"type" => "execution", "shape" => "tuple", "suffix" => 2, "override" => false}
          ]

      cases =
        Enum.map(@error_shapes, &("ERROR-001/" <> &1)) ++
          ["ERROR-001/retry_defaults", "ERROR-001/retry_override"]

      run_check(
        "error_outputs",
        generator,
        unquote(suite),
        unquote(runs),
        unquote(time),
        ["ERROR-001"],
        cases,
        examples,
        &error_case/1
      )
    end
  end

  @tag :property
  test "independent models reject isolated wrong state and effect order" do
    expected = %{"accepted" => true, "value" => 9, "selected" => 0, "effects" => [1, 2]}

    valid =
      Agent.new!(name: "model_mutation", schema: state_schema())
      |> Agent.instantiate!(id: "mutation", state: %{value: 9, selected: 0})

    assert_candidate({:ok, valid, [Directive.stop(1), Directive.stop(2)]}, expected)

    assert_raise ExUnit.AssertionError, fn ->
      assert_candidate(
        {:ok, %{valid | state: %{value: 10, selected: 0}},
         [Directive.stop(1), Directive.stop(2)]},
        expected
      )
    end

    assert_raise ExUnit.AssertionError, fn ->
      assert_candidate({:ok, valid, [Directive.stop(2), Directive.stop(1)]}, expected)
    end
  end

  defp run_check(id, generator, suite, runs, time, contracts, cases, examples, assertion) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido-#{id}-#{System.pid()}-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, JSON.encode!(%{format: 1, property: id, input: hd(examples)}))

    try do
      Fuzz.check(
        id,
        generator,
        [
          fuzz: suite == :fuzz,
          max_runs:
            if(suite == :fuzz and id in ["agent_definitions", "error_outputs"],
              do: 1_000,
              else: runs
            ),
          max_run_time: time,
          max_shrinking_steps: 100,
          timeout: 180_000,
          contracts: contracts,
          contract_cases: cases,
          examples: examples,
          corpus: [path]
        ],
        assertion
      )
    after
      File.rm!(path)
    end
  end

  defp definition_case(input) do
    metadata = %{
      "count" => input["count"],
      "enabled" => input["enabled"],
      "label" => input["label"]
    }

    schema = Zoi.object(%{count: Zoi.integer()})
    attrs = %{name: "property_definition", schema: schema, metadata: metadata}

    expected = %{
      "type" => "jido.agent",
      "version" => 2,
      "module" => "agent/core",
      "vsn" => nil,
      "name" => "property_definition",
      "description" => nil,
      "schema" => "schema/core",
      "plugins" => [],
      "routes" => [],
      "metadata" => %{
        "$type" => "map",
        "entries" => for({key, value} <- Enum.sort(metadata), do: [key, value])
      }
    }

    registry =
      Registry.new!(%{"agent/core" => {:agent, Agent}, "schema/core" => {:schema, schema}})

    {:ok, definition} = Agent.new(attrs)
    original = definition
    mode = input["mode"]

    case mode do
      "unknown_key" ->
        assert {:error, %Error.ValidationError{}} = Agent.new(Map.put(attrs, :extra, true))

      "incomplete_id" ->
        assert {:error, %Error.ValidationError{}} =
                 Codec.encode(%{definition | state: %{count: input["count"]}}, registry)

      "incomplete_state" ->
        assert {:error, %Error.ValidationError{}} =
                 Codec.encode(%{definition | id: "missing-state"}, registry)

      _ ->
        source =
          if mode == "definition",
            do: definition,
            else:
              Agent.instantiate!(definition,
                id: "property-instance",
                state: %{count: input["count"]}
              )

        source =
          if mode == "ignored_live_state",
            do: %{source | state: %{count: "not encoded"}},
            else: source

        assert {:ok, ^expected} = Codec.encode(source, registry)
        assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(expected)), registry)
        assert definition.id == nil and definition.state == nil
    end

    assert definition === original
    ["AGT-001/" <> mode]
  end

  defp state_schema, do: Zoi.object(%{value: Zoi.integer(), selected: Zoi.integer()})

  defp selection_case(input) do
    mode = input["mode"]

    module =
      case mode do
        "custom" -> CustomSelector
        "wrong_source" -> WrongSource
        _ -> Agent
      end

    definition =
      Agent.new!(
        name: "property_selection",
        module: module,
        schema: state_schema(),
        routes: [
          {"property.exact", First, defaults: %{delta: 4}, priority: 10},
          {"property.*", Second, defaults: %{delta: 9}},
          {"flow.run", RoutedFlow}
        ]
      )

    agent =
      Agent.instantiate!(definition, id: "selection", state: %{value: input["base"], selected: 0})

    {_agent, _model} =
      Enum.reduce(input["deltas"], {agent, input["base"]}, fn delta, {current, model} ->
        expected = selection_model(mode, model, delta)
        signal = selection_signal(mode, delta)
        result = Agent.cmd(current, signal)
        next = assert_selection(result, expected, current)
        assert current.state.value == model
        assert Agent.definition(next) === definition
        # The next expectation derives from this independent JSON model only.
        {next, if(expected["accepted"], do: expected["value"], else: model)}
      end)

    assert agent.state == %{value: input["base"], selected: 0}
    ["TURN-001/" <> mode]
  end

  defp selection_model(mode, value, delta) do
    accepted = mode not in ~w(wrong_source missing invalid_type invalid_envelope bad_data)
    selected = if mode in ~w(wildcard flow), do: 2, else: 1
    amount = if mode == "nil_data", do: 4, else: delta

    error_type =
      case mode do
        mode when mode in ~w(missing invalid_type) -> "routing_error"
        "invalid_envelope" -> "config_error"
        _ -> "validation_error"
      end

    %{
      "accepted" => accepted,
      "value" => value + amount,
      "selected" => selected,
      "error_type" => error_type
    }
  end

  defp selection_signal(mode, delta) do
    type =
      case mode do
        "wildcard" -> "property.other"
        "flow" -> "flow.run"
        "missing" -> "missing.route"
        _ -> "property.exact"
      end

    data =
      case mode do
        "nil_data" -> nil
        "keyword_data" -> [delta: 100, delta: delta]
        "bad_data" -> "not route input"
        _ -> %{delta: delta}
      end

    signal = Signal.new!(type, data, source: "/property")

    case mode do
      "invalid_type" -> %{signal | type: :invalid}
      "invalid_envelope" -> %{signal | id: ""}
      _ -> signal
    end
  end

  defp assert_selection({:ok, next, []}, %{"accepted" => true} = expected, _current) do
    assert next.state == %{value: expected["value"], selected: expected["selected"]}
    next
  end

  defp assert_selection({:error, error}, %{"accepted" => false} = expected, current) do
    assert is_exception(error)
    assert Atom.to_string(Error.to_map(error).type) == expected["error_type"]
    current
  end

  defp assert_selection(result, expected, _current),
    do: flunk("selection differs from model: #{inspect({result, expected})}")

  defp candidate_case(input) do
    target = if input["flow"], do: candidate_flow(), else: Candidate

    definition =
      Agent.new!(
        name: "property_candidate",
        schema: state_schema(),
        routes: [{"candidate.run", target}]
      )

    original = Agent.instantiate!(definition, id: "candidate", state: %{value: 7, selected: 0})
    params = %{mode: input["mode"], value: input["value"], effects: input["effects"]}

    expected = %{
      "accepted" => input["mode"] == "valid",
      "value" => input["value"],
      "selected" => 0,
      "effects" => input["effects"]
    }

    assert_candidate(
      Agent.cmd(original, Signal.new!("candidate.run", params, source: "/property")),
      expected
    )

    assert original.state == %{value: 7, selected: 0}
    assert Agent.definition(original) === definition
    ["TURN-002/" <> input["mode"]]
  end

  defp candidate_flow do
    Jido.Flow.new!(
      name: "property_candidate_flow",
      components: [
        Jido.Flow.Step.new!(
          name: "candidate",
          action: Candidate,
          params: Jido.Flow.Ref.input(nil)
        )
      ],
      output: Jido.Flow.Ref.result("candidate")
    )
  end

  defp assert_candidate({:ok, agent, directives}, %{"accepted" => true} = expected) do
    assert agent.state == %{value: expected["value"], selected: expected["selected"]}
    assert Enum.map(directives, & &1.reason) == expected["effects"]
    assert Enum.all?(directives, &is_struct(&1, Directive.Stop))
  end

  defp assert_candidate({:error, error}, %{"accepted" => false}) do
    assert is_exception(error)

    assert Map.keys(Error.to_map(error)) |> Enum.sort() == [
             :details,
             :message,
             :retryable?,
             :type
           ]
  end

  defp assert_candidate(result, expected),
    do: flunk("candidate differs from model: #{inspect({result, expected})}")

  defp error_case(input) do
    marker = "PRIVATE_CORE_PROPERTY_#{input["suffix"]}"
    payload = error_payload(input["shape"], marker)
    details = %{public: "visible", payload: payload, stacktrace: [{marker, marker}]}

    details =
      if is_boolean(input["override"]),
        do: Map.put(details, :retryable?, input["override"]),
        else: details

    error = make_error(input["type"], details)
    expected = error_model(input["type"], input["override"])
    projection = Error.to_map(error)
    assert Atom.to_string(projection.type) == expected["type"]
    assert projection.retryable? == expected["retry"]
    assert Error.retryable?({:error, error}) == expected["retry"]
    assert projection.details.public == "visible"
    encoded = JSON.encode!(projection)
    refute String.contains?(encoded, marker)
    assert byte_size(encoded) < 30_000
    assert Map.keys(projection) |> Enum.sort() == [:details, :message, :retryable?, :type]

    [
      "ERROR-001/" <> input["shape"],
      if(is_nil(input["override"]),
        do: "ERROR-001/retry_defaults",
        else: "ERROR-001/retry_override"
      )
    ]
  end

  defp error_model(type, override) do
    types = %{
      "validation" => "validation_error",
      "execution" => "execution_error",
      "routing" => "routing_error",
      "timeout" => "timeout",
      "compensation" => "compensation_error",
      "internal" => "internal"
    }

    %{
      "type" => Map.fetch!(types, type),
      "retry" => if(is_boolean(override), do: override, else: type != "validation")
    }
  end

  defp make_error("validation", details),
    do: Error.validation_error("property error", details: details)

  defp make_error("execution", details),
    do: Error.execution_error("property error", details: details)

  defp make_error("routing", details), do: Error.routing_error("property error", details: details)
  defp make_error("timeout", details), do: Error.timeout_error("property error", details: details)

  defp make_error("compensation", details),
    do: Error.compensation_error("property error", details: details)

  defp make_error("internal", details),
    do: Error.internal_error("property error", details: details)

  defp error_payload("atom_key", marker), do: %{api_key: marker, keep: 1}
  defp error_payload("string_key", marker), do: %{"Authorization" => marker, "keep" => 1}
  defp error_payload("keyword", marker), do: [password: marker, keep: 1]
  defp error_payload("mixed", marker), do: [1, {:token, marker}, "keep"]
  defp error_payload("tuple", marker), do: {{:private_key, marker}, %{keep: 1}}
  defp error_payload("improper", marker), do: [1 | %{secret: marker}]

  defp error_payload("deep", marker),
    do: Enum.reduce(1..10, %{secret: marker}, fn _, value -> %{next: value} end)

  defp error_payload("wide", marker),
    do: Enum.map(1..30, fn n -> %{secret: marker, keep: n, text: String.duplicate("x", 800)} end)

  defp error_payload("invalid_binary", marker), do: %{secret: marker <> <<255>>, keep: <<255>>}
end
