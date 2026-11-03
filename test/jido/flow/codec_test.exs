defmodule Jido.Flow.CodecTest do
  use Covenant.Case, component: "jido_action.codec", async: false
  @moduletag obligation: "jido_action.codec.I7"

  alias Jido.Catalog
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow
  alias Jido.Flow.Codec
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.Error
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.CodecRegistry
  alias JidoActionTest.Fixtures.FlowAuthoring
  alias JidoActionTest.Fixtures.InlineAuthoring
  alias JidoActionTest.Fixtures.InlineParityFlow
  alias JidoActionTest.Fixtures.NestedFlow
  alias JidoActionTest.Fixtures.Actions.{Add, Multiply}

  defmodule InlineProbeFlow do
    @moduledoc false

    use Jido.Flow, name: "inline_codec_probe"

    flow do
      step "mark", marker <- value("stored") do
        send(Jido.Flow.CodecTest.InlineProbeObserver, {:inline_codec_body, marker, self()})
        {:ok, %{marker: marker}}
      end

      output(result("mark"))
    end
  end

  setup context do
    if context[:inline_probe] do
      observer_name = __MODULE__.InlineProbeObserver
      assert Process.register(self(), observer_name)

      # The VM removes this registration on every exit of the test owner.
      on_exit(fn -> assert Process.whereis(observer_name) == nil end)
    end

    :ok
  end

  test "the Flow codec contract uses document version two" do
    assert Jido.Flow.Codec.type() == "jido.flow"
    assert Jido.Flow.Codec.version() == 2
    assert Jido.Flow.Codec.target() == Jido.Flow
  end

  test "inline Steps use the exact version 2 stored call fields" do
    assert {:ok, document} = Codec.encode(InlineParityFlow.flow(), InlineAuthoring.registry())
    assert document["vsn"] == 2

    for step <- document["components"] do
      assert step["kind"] == "call"
      assert Enum.sort(Map.keys(step)) == ["call", "kind", "meta", "name", "needs"]
    end

    [empty, named, multiple, sole_map] = document["components"]
    assert empty["call"]["params"] == %{"$type" => "map", "entries" => []}

    assert [%{"key" => %{"$type" => "atom", "id" => "atoms/name", "vsn" => 1}}] =
             named["call"]["params"]["entries"]

    assert Enum.map(multiple["call"]["params"]["entries"], & &1["key"]["id"]) ==
             ["atoms/name", "atoms/prefix"]

    assert sole_map["call"]["params"] == %{
             "$ref" => %{
               "source" => "input",
               "component" => nil,
               "path" => [%{"$type" => "atom", "id" => "atoms/payload", "vsn" => 1}]
             }
           }
  end

  test "stored Catalog references include and check vsn" do
    registry = InlineAuthoring.registry()
    schema = Jido.Joi.object(%{})
    flow = %{InlineParityFlow.flow() | schema: schema, output_schema: schema}
    assert {:ok, document} = Codec.encode(flow, registry)

    assert %{"id" => _id, "vsn" => 1} = document["schema"]
    assert %{"id" => _id, "vsn" => 1} = document["output_schema"]
    [step | _rest] = document["components"]
    assert %{"id" => _id, "vsn" => 1} = step["call"]["target"]

    invalid = put_in(step, ["call", "target", "vsn"], 2)

    assert {:error,
            %InvalidDefinitionError{
              message: "flow catalog reference has unsupported vsn",
              details: %{
                vsn: 2,
                supported_vsns: [1],
                path: ["components", 0, "call", "target", "vsn"]
              }
            }} = Codec.decode(replace_component(document, 0, invalid), registry)
  end

  @tag :inline_probe
  test "stored inline Steps reject body, code, callable, and run fields without work" do
    registry = inline_probe_registry()
    assert {:ok, document} = Codec.encode(InlineProbeFlow.flow(), registry)
    [step] = document["components"]

    for field <- ["body", "code", "callable", "run"] do
      invalid = replace_component(document, 0, Map.put(step, field, "send(self(), :work)"))

      assert {:error,
              %InvalidDefinitionError{
                message: _message,
                details: %{key: ^field, path: ["components", 0, ^field]}
              }} = invalid |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)
    end

    # The synchronous decode calls above are the barrier for this mailbox check.
    refute_received {:inline_codec_body, _, _}
  end

  @tag :inline_probe
  test "inline Action and binding atom identifiers must exist in the trusted Catalog" do
    flow = InlineProbeFlow.flow()
    registry = inline_probe_registry()
    assert {:ok, document} = Codec.encode(flow, registry)
    [step] = document["components"]
    unknown_action = "untrusted/inline-action/#{System.unique_integer([:positive])}"
    unknown_atom = "untrusted/inline-binding/#{System.unique_integer([:positive])}"

    refute existing_atom?(unknown_action)
    refute existing_atom?(unknown_atom)

    for {identifier, message, path} <- [
          {unknown_action, "unknown flow catalog reference", ["components", 0, "call", "target", "id"]},
          {"flows/not-an-action", "flow catalog reference has the wrong entry kind",
           ["components", 0, "call", "target", "id"]}
        ] do
      invalid =
        replace_component(
          document,
          0,
          JidoActionTest.StoredFields.update(step, %{
            "action" => %{"id" => identifier, "vsn" => 1}
          })
        )

      assert {:error,
              %InvalidDefinitionError{
                message: ^message,
                details: %{identifier: ^identifier, path: ^path}
              }} = Codec.decode(invalid, registry)
    end

    missing_binding =
      registry
      |> Catalog.list()
      |> Enum.reject(&(&1.id == "atoms/marker" and &1.vsn == 1))
      |> Catalog.new!()

    assert {:error, %InvalidDefinitionError{details: %{kind: :atom}}} =
             Codec.encode(flow, missing_binding)

    assert {:error,
            %InvalidDefinitionError{
              message: "unknown flow catalog reference",
              details: %{
                identifier: "atoms/marker",
                path: ["components", 0, "call", "params", "entries", 0, "key", "id"]
              }
            }} = Codec.decode(document, missing_binding)

    [entry] = step["call"]["params"]["entries"]

    untrusted_entry = %{
      entry
      | "key" => %{"$type" => "atom", "id" => unknown_atom, "vsn" => 1}
    }

    invalid = put_in(step, ["call", "params", "entries"], [untrusted_entry])

    assert {:error,
            %InvalidDefinitionError{
              message: "unknown flow catalog reference",
              details: %{identifier: ^unknown_atom, kind: :atom}
            }} = Codec.decode(replace_component(document, 0, invalid), registry)

    refute existing_atom?(unknown_action)
    refute existing_atom?(unknown_atom)
    refute_received {:inline_codec_body, _, _}
  end

  @tag :inline_probe
  test "lookup, validation, inspection, and JSON operations do not run an inline body" do
    action = InlineProbeFlow.step_action(:mark)
    marker = make_ref()

    assert Jido.Exec.run(action, %{marker: marker}) == {:ok, %{marker: marker}}
    assert_received {:inline_codec_body, ^marker, worker}
    refute worker == self()
    refute_received {:inline_codec_body, _, _}

    flow = InlineProbeFlow.flow()
    registry = inline_probe_registry()

    assert InlineProbeFlow.step_action("mark") == action
    assert %{"mark" => %{call: %{target: ^action, params: _params}}} = flow.components
    assert {:ok, ^flow} = Flow.validate(flow)
    assert {:ok, ^flow} = Jido.Exec.Compiler.validate(flow)
    assert {:ok, _} = Flow.explain(flow)
    assert is_map(Flow.to_map(flow))
    assert {:ok, document} = Codec.encode(flow, registry)

    assert {:ok, ^flow} =
             document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)

    assert {:ok, ^flow} = Codec.diagnose(document, registry)
    assert {:ok, temporary_document, temporary_registry} = Codec.encode(flow)
    assert {:ok, ^flow} = Codec.decode(temporary_document, temporary_registry)
    refute_received {:inline_codec_body, _, _}
  end

  test "JSON bytes round trip to the equal canonical Flow" do
    flow = FlowAuthoring.mixed_flow!()
    registry = CodecRegistry.mixed()

    assert {:ok, document} = Codec.encode(flow, registry)
    assert document["vsn"] == 2

    assert Enum.map(document["components"], & &1["kind"]) ==
             ["call", "iterate", "map", "call", "reduce", "choice"]

    json = Jason.encode!(document)
    decoded_document = Jason.decode!(json)

    assert {:ok, decoded} = Codec.decode(decoded_document, registry)
    assert decoded == flow
    assert {:ok, ^document} = Codec.encode(decoded, registry)
    assert {:ok, ^flow} = Codec.diagnose(decoded_document, registry)
  end

  test "version one documents reject with an explicit Dispatch migration error" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)
    version_one = Map.put(document, "vsn", 1)

    assert {:error,
            %InvalidDefinitionError{
              message:
                "stored Flow document vsn 1 requires migration to vsn 2; Dispatch cannot be migrated automatically",
              details: %{path: ["vsn"]}
            }} = Codec.decode(version_one, registry)

    assert {:error,
            [
              %Jido.Codec.Issue{
                code: :unsupported_document,
                path: ["vsn"],
                details: %{type: "jido.flow", vsn: 1, supported_vsns: [2]}
              }
            ]} =
             Jido.Codec.decode(version_one, catalog: registry, codec: Jido.Flow.Codec)
  end

  test "current version preserves diagnostics for nested structs" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)

    document = %{
      document
      | "vsn" => 2,
        "components" => [hd(document["components"])],
        "output" => %URI{path: "/flow"}
    }

    assert {:error, %Error.Invalid{errors: [error]}} = Codec.diagnose(document, registry)
    assert error.message == "stored Flow data has an invalid tagged value"
    assert error.details == %{path: ["output"]}
  end

  test "all component kinds round trip needs in the current document version" do
    registry = CodecRegistry.mixed()
    flow = all_component_flow!()
    assert {:ok, document} = Codec.encode(flow, registry)
    assert document["vsn"] == 2

    assert Enum.map(document["components"], & &1["kind"]) ==
             ["call", "choice", "iterate", "map", "parallel", "reduce", "call", "invoke"]

    for component <- document["components"] do
      assert Map.has_key?(component, "needs")
      refute Map.has_key?(component, "after")
    end

    assert {:ok, ^flow} = Codec.decode(document, registry)
    assert {:ok, ^flow} = document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)
  end

  test "stored components reject after without conversion" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(all_component_flow!(), registry)

    for {component, index} <- Enum.with_index(document["components"]) do
      legacy = component |> Map.delete("needs") |> Map.put("after", [])
      invalid = replace_component(document, index, legacy)

      assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

      assert Enum.sort(Enum.map(errors, & &1.details.path)) == [
               ["components", index, "after"]
             ]

      assert {:error,
              %InvalidDefinitionError{
                message: _message,
                details: %{key: "after", path: ["components", ^index, "after"]}
              }} = Codec.decode(invalid, registry)
    end
  end

  test "stored needs field errors retain the JSON boundary path" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(all_component_flow!(), registry)
    [step | _rest] = document["components"]

    invalid_steps = [
      %{step | "needs" => 42},
      %{step | "needs" => [42]}
    ]

    for invalid_step <- invalid_steps do
      invalid = replace_component(document, 0, invalid_step)

      assert {:error, %InvalidDefinitionError{details: %{path: path}}} =
               Codec.decode(invalid, registry)

      assert path in [["components", 0, "needs"], ["components", 0, "needs", 0]]
    end
  end

  test "encode/1 rejects a non-canonical Flow" do
    raw_flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "raw_codec",
        components: [%{kind: :step, name: "add", action: Add, params: %{a: 1, b: 2}}],
        output: Ref.result("add")
      })
      |> Map.replace!(:schema, nil)
      |> Map.replace!(:output_schema, nil)

    assert {:error,
            %InvalidDefinitionError{
              message: "Flow artifact contains non-canonical data",
              details: %{path: [:schema], reason: :non_canonical}
            }} = Jido.Exec.Compiler.validate(raw_flow)

    assert {:error, %InvalidDefinitionError{details: %{path: [:schema]}}} =
             Codec.encode(raw_flow)
  end

  test "diagnose returns ordered errors from independent document branches" do
    flow = FlowAuthoring.mixed_flow!()
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(flow, registry)

    step_index = component_index(document, "load")
    choice_index = component_index(document, "route")
    step = component(document, "load")
    choice = component(document, "route")
    [option] = choice["options"]

    step = step |> Map.put("needs", 42) |> JidoActionTest.StoredFields.target(42)

    option =
      option
      |> Map.put("condition", "invalid")
      |> JidoActionTest.StoredFields.target(42)

    fallback =
      JidoActionTest.StoredFields.target(
        choice["fallback"],
        %{"id" => "actions/missing", "vsn" => 1}
      )

    choice = %{choice | "options" => [option], "fallback" => fallback}

    output = %{
      "$type" => "map",
      "entries" => [
        %{
          "key" => "first",
          "value" => %{"$type" => "atom", "id" => 42}
        },
        %{
          "key" => "second",
          "value" => %{"$type" => "atom", "id" => "atoms/missing"}
        }
      ]
    }

    invalid =
      document
      |> replace_component(step_index, step)
      |> replace_component(choice_index, choice)
      |> Map.put("output", output)

    assert {:error, %Error.Invalid{errors: errors} = aggregate} =
             Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) == [
             ["components", step_index, "needs"],
             ["components", step_index, "call", "target"],
             ["components", choice_index, "options", 0, "condition"],
             ["components", choice_index, "options", 0, "call", "target"],
             ["components", choice_index, "fallback", "target", "id"],
             ["output", "entries", 0, "value", "id"],
             ["output", "entries", 1, "value", "id"]
           ]

    assert %{details: %{errors: mapped_errors}} = Error.to_map(aggregate)
    assert length(mapped_errors) == 7
  end

  test "diagnose reports all unknown graph references without cycle cascades" do
    flow = FlowAuthoring.math_flow!()
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(flow, registry)

    [first, second] = document["components"]
    first = %{first | "needs" => ["missing-first"]}
    second = %{second | "needs" => ["missing-second"]}

    output = %{
      "$ref" => %{
        "source" => "result",
        "component" => "missing-output",
        "path" => []
      }
    }

    invalid = %{document | "components" => [first, second], "output" => output}

    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

    assert Enum.map(errors, fn error ->
             {error.details.owner, error.details.component, error.details.path}
           end) == [
             {:output, "missing-output", ["output"]},
             {"add_one", "missing-first", ["components", 0]},
             {"double", "missing-second", ["components", 1]}
           ]
  end

  test "diagnose reports Handoff path and output errors at exact paths" do
    registry = CodecRegistry.mixed()

    handoff_flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "stored_handoff",
        components: [
          %{kind: :handoff, name: "next", selector: Add, params: %{value: 1}}
        ],
        output: Ref.result("next")
      })

    assert {:ok, handoff_document} = Codec.encode(handoff_flow, registry)
    assert {:ok, math_document} = Codec.encode(FlowAuthoring.math_flow!(), registry)

    [handoff] = handoff_document["components"]
    [step | _rest] = math_document["components"]

    wrapped_output = %{
      "$type" => "map",
      "entries" => [%{"key" => "value", "value" => handoff_document["output"]}]
    }

    invalid = %{
      handoff_document
      | "components" => [handoff, step],
        "output" => wrapped_output
    }

    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

    assert Enum.map(errors, &{Exception.message(&1), &1.details.path}) == [
             {"Handoff must be the final component in the Flow", ["components", 0]},
             {"Flow output must be the complete Handoff result", ["output"]}
           ]
  end

  test "diagnose reports constructor expression errors at stored document paths" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.math_flow!(), registry)
    [first, second] = document["components"]
    item = %{"$ref" => %{"source" => "item", "component" => nil, "path" => []}}

    stored_map = fn entries ->
      %{
        "$type" => "map",
        "entries" => Enum.map(entries, fn {key, value} -> %{"key" => key, "value" => value} end)
      }
    end

    invalid = %{
      document
      | "components" => [
          JidoActionTest.StoredFields.update(first, %{
            "params" => stored_map.([{"x", stored_map.([{"y", item}])}])
          }),
          JidoActionTest.StoredFields.update(second, %{
            "params" => stored_map.([{"components", [stored_map.([]), item]}])
          })
        ],
        "output" => stored_map.([{"value", item}])
    }

    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) == [
             ["components", 0, "call", "params", "entries", 0, "value", "entries", 0, "value"],
             ["components", 1, "call", "params", "entries", 0, "value", 1],
             ["output", "entries", 0, "value"]
           ]
  end

  test "diagnose collects canonical errors from each Choice option and fallback" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)
    choice_index = component_index(document, "route")
    choice = component(document, "route")
    [option] = choice["options"]
    item = %{"$ref" => %{"source" => "item", "component" => nil, "path" => []}}

    choice = %{
      choice
      | "options" => [
          JidoActionTest.StoredFields.update(option, %{"params" => item}),
          JidoActionTest.StoredFields.update(option, %{"name" => "second", "params" => item})
        ],
        "fallback" => JidoActionTest.StoredFields.update(choice["fallback"], %{"params" => item})
    }

    invalid = replace_component(document, choice_index, choice)

    assert {:error, %Error.Invalid{errors: [first | _] = errors}} =
             Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) == [
             ["components", choice_index, "options", 0, "call", "params"],
             ["components", choice_index, "options", 1, "call", "params"],
             ["components", choice_index, "fallback", "params"]
           ]

    assert Codec.decode(invalid, registry) == {:error, first}
  end

  test "diagnose collects Iterate state errors before independent completion errors" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)
    iterate_index = component_index(document, "loop")
    iterate = component(document, "loop")

    for {field, source} <- [{"initial", "state"}, {"update", "item"}] do
      invalid_ref = %{"$ref" => %{"source" => source, "component" => nil, "path" => []}}

      invalid_iterate = %{
        iterate
        | "state" => Map.put(iterate["state"], field, invalid_ref),
          "completion" => "invalid"
      }

      invalid = replace_component(document, iterate_index, invalid_iterate)

      assert {:error, %Error.Invalid{errors: [first | _] = errors}} =
               Codec.diagnose(invalid, registry)

      assert Enum.map(errors, & &1.details.path) == [
               ["components", iterate_index, "state", field],
               ["components", iterate_index, "completion"]
             ]

      assert Codec.decode(invalid, registry) == {:error, first}
    end
  end

  test "diagnose stops at document safety limits" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)
    unsafe = %{document | "output" => List.duplicate(0, 10_001)}

    assert {:error,
            %Error.Invalid{
              errors: [
                %InvalidDefinitionError{
                  message: "stored Flow collection exceeds its size limit"
                }
              ]
            }} = Codec.diagnose(unsafe, registry)
  end

  test "diagnose contains invalid public boundaries and root envelopes" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)

    for {invalid, invalid_registry} <- [
          {:not_a_document, registry},
          {document, :not_a_registry}
        ] do
      assert {:error, %Error.Invalid{errors: [_error]}} =
               Codec.diagnose(invalid, invalid_registry)
    end

    envelope_errors =
      document
      |> Map.delete("type")
      |> Map.put("vsn", 99)
      |> Map.put("extra", true)

    assert {:error, %Error.Invalid{errors: envelope}} =
             Codec.diagnose(envelope_errors, registry)

    assert Enum.map(envelope, & &1.details.path) == [["type"]]

    missing_fields =
      Enum.reduce(
        ["name", "description", "schema", "output_schema", "components", "output"],
        document,
        &Map.delete(&2, &1)
      )

    assert {:error, %Error.Invalid{errors: missing}} = Codec.diagnose(missing_fields, registry)
    assert Enum.map(missing, & &1.details.path) == [["name"], ["components"], ["output"]]

    invalid_fields =
      Map.merge(document, %{
        "name" => 42,
        "description" => 42,
        "schema" => 42,
        "output_schema" => 42,
        "components" => :not_a_list,
        "output" => %{"bad" => true}
      })

    assert {:error, %Error.Invalid{errors: invalid}} = Codec.diagnose(invalid_fields, registry)
    assert length(invalid) == 6

    assert {:ok, nil_description} = Codec.diagnose(%{document | "description" => nil}, registry)
    assert nil_description.description == nil

    assert {:error, %Error.Invalid{errors: [name_error]}} =
             Codec.diagnose(%{document | "name" => ""}, registry)

    assert name_error.details.path == ["name"]

    assert {:error, {:invalid_catalog_manifest, __MODULE__, _reason}} =
             Catalog.from_targets(__MODULE__, :jido, %{
               {"schemas/bad", 1} => {:schema, fn -> :not_static end}
             })
  end

  test "diagnose collects required fields for every component kind" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)
    step = component(document, "load")
    subflow = component(document, "child")
    choice = component(document, "route")
    map = component(document, "mapped")
    reduce = component(document, "reduced")
    iterate = component(document, "loop")

    step =
      step
      |> Map.delete("call")
      |> Map.delete("meta")
      |> Map.put("extra", true)

    subflow = JidoActionTest.StoredFields.update(subflow, %{"flow" => 42, "needs" => ~c"*"})
    choice = choice |> Map.delete("options") |> Map.delete("fallback")

    map =
      map
      |> Map.delete("collection")
      |> Map.delete("call")
      |> Map.put("on_error", "unsupported")

    reduce =
      reduce
      |> Map.delete("initial")
      |> Map.delete("call")
      |> Map.put("collection", %{"bad" => true})
      |> JidoActionTest.StoredFields.target(42)

    iterate =
      iterate
      |> Map.delete("call")
      |> Map.delete("state")
      |> Map.delete("completion")
      |> Map.put("max_iterations", 0)

    invalid =
      document
      |> replace_named_component("load", step)
      |> replace_named_component("child", subflow)
      |> replace_named_component("route", choice)
      |> replace_named_component("mapped", map)
      |> replace_named_component("reduced", reduce)
      |> replace_named_component("loop", iterate)

    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)
    assert length(errors) == 17

    assert errors
           |> Enum.map(& &1.details.path)
           |> Enum.all?(&match?(["components", _index | _rest], &1))
  end

  test "diagnose collects nested reference, condition, list, and map errors" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)
    choice_index = component_index(document, "route")
    choice = component(document, "route")
    [option] = choice["options"]

    condition = %{
      "$expr" => %{
        "operator" => "all",
        "operands" => [true, false]
      }
    }

    option = %{option | "condition" => condition}
    choice = %{choice | "options" => [nil, option]}

    bad_ref = %{
      "$ref" => %{
        "source" => "unsupported",
        "component" => 42,
        "path" => :not_a_list,
        "extra" => true
      }
    }

    output = [
      bad_ref,
      %{"$type" => "atom"},
      %{"$type" => "map", "entries" => :not_a_list}
    ]

    invalid = replace_component(document, choice_index, choice) |> Map.put("output", output)

    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)
    assert length(errors) == 8

    duplicate_map = %{
      "$type" => "map",
      "entries" => [
        %{"key" => "same", "value" => 1},
        %{"key" => "same", "value" => 2}
      ]
    }

    assert {:error, %Error.Invalid{errors: [duplicate]}} =
             Codec.diagnose(%{document | "output" => duplicate_map}, registry)

    assert duplicate.details.path == ["output", "entries", 1, "key"]

    invalid_entries = %{
      "$type" => "map",
      "entries" => [
        nil,
        %{"key" => "missing-value"},
        %{"value" => 1},
        %{"key" => %{"$type" => "map", "entries" => []}, "value" => 1}
      ]
    }

    assert {:error, %Error.Invalid{errors: entry_errors}} =
             Codec.diagnose(%{document | "output" => invalid_entries}, registry)

    assert length(entry_errors) == 4
  end

  test "an atom record with an extra field reports only the extra field" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)

    atom = %{"$type" => "atom", "id" => "atoms/go", "vsn" => 1, "extra" => true}

    assert {:error, %Error.Invalid{errors: [error]}} =
             Codec.diagnose(%{document | "output" => atom}, registry)

    assert error.details.path == ["output", "extra"]
  end

  test "diagnose distinguishes duplicate names and dependency cycles" do
    registry = CodecRegistry.mixed()

    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "diagnostic_graph",
        components: [
          %{kind: :step, name: "first", action: Add},
          %{kind: :step, name: "second", action: Add}
        ],
        output: %{}
      })

    assert {:ok, document} = Codec.encode(flow, registry)
    [first, second] = document["components"]

    duplicate = %{document | "components" => [first, %{second | "name" => first["name"]}]}

    assert {:error, %Error.Invalid{errors: [duplicate_error]}} =
             Codec.diagnose(duplicate, registry)

    assert duplicate_error.details.path == ["components", 1, "name"]

    cycle = %{
      document
      | "components" => [
          %{first | "needs" => [second["name"]]},
          %{second | "needs" => [first["name"]]}
        ]
    }

    assert {:error, %Error.Invalid{errors: [cycle_error]}} = Codec.diagnose(cycle, registry)
    assert cycle_error.message == "flow dependency graph contains a cycle"
    assert cycle_error.details.path == ["components"]
  end

  test "Codec rejects invalid UTF-8 at every portable string boundary" do
    invalid = <<255>>
    registry = CodecRegistry.storage()

    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "utf8_boundary",
        description: "valid",
        components: [
          %{kind: :step, name: "stored", action: Add, params: %{value: "valid"}}
        ],
        output: Ref.result("stored")
      })

    node = flow.components["stored"]
    instruction = node.call

    invalid_flows = [
      %{flow | description: invalid},
      put_in(flow.components["stored"].call, Map.put(instruction, :params, %{value: invalid})),
      put_in(
        flow.components["stored"].call,
        Map.put(instruction, :params, %{invalid => "value"})
      ),
      put_in(flow.components["stored"].meta, %{owner: invalid})
    ]

    for invalid_flow <- invalid_flows do
      assert {:error, %InvalidDefinitionError{}} = Codec.encode(invalid_flow, registry)
    end

    assert {:error, _reason} =
             Catalog.from_targets(__MODULE__, :jido, %{invalid => {:action, Add}})

    assert {:ok, document} = Codec.encode(flow, registry)

    assert {:error, %InvalidDefinitionError{}} =
             Codec.decode(%{document | "description" => invalid}, registry)

    assert {:ok, decoded} =
             document
             |> Jason.encode!()
             |> Jason.decode!()
             |> Codec.decode(registry)

    assert decoded == flow
  end

  test "the decoder rejects an unsupported version and missing component kinds" do
    {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), CodecRegistry.mixed())

    assert {:error,
            %InvalidDefinitionError{
              message: "stored Flow document vsn must be 2",
              details: %{path: ["vsn"]}
            }} =
             Codec.decode(%{document | "vsn" => 99}, CodecRegistry.mixed())

    for malformed <- [
          %{document | "type" => "wrong", "vsn" => 2},
          %{document | "type" => "wrong", "vsn" => 1},
          %{document | "type" => "", "vsn" => 99},
          document |> Map.delete("type") |> Map.put("", "jido.flow") |> Map.put("vsn", 99)
        ] do
      assert {:error,
              %InvalidDefinitionError{
                message: "stored Flow document type must be jido.flow",
                details: %{path: ["type"]}
              }} = Codec.decode(malformed, CodecRegistry.mixed())
    end

    [first | rest] = document["components"]
    invalid = %{document | "components" => [Map.delete(first, "kind") | rest]}
    assert {:error, %InvalidDefinitionError{}} = Codec.decode(invalid, CodecRegistry.mixed())
  end

  test "Codec rejects invalid public boundary values and root records" do
    registry = CodecRegistry.mixed()
    flow = FlowAuthoring.mixed_flow!()
    assert {:ok, document} = Codec.encode(flow, registry)

    assert {:error, %InvalidDefinitionError{}} = Codec.encode(:invalid, registry)
    assert {:error, %InvalidDefinitionError{}} = Codec.encode(flow, :invalid)
    assert {:error, %InvalidDefinitionError{}} = Codec.decode(:invalid, registry)
    assert {:error, %InvalidDefinitionError{}} = Codec.decode(document, :invalid)

    for invalid <- [Map.delete(document, "name"), Map.put(document, "extra", true)] do
      assert {:error, %InvalidDefinitionError{}} = Codec.decode(invalid, registry)
    end
  end

  test "Action and Flow identifiers have distinct trusted kinds" do
    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "one_subflow",
        components: [%{kind: :subflow, name: "child", flow: NestedFlow}],
        output: Ref.result("child")
      })

    wrong_registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"targets/child", 1} => {:action, NestedFlow},
        {"schemas/map", 1} => {:schema, Jido.Joi.map()}
      })

    assert {:error, %InvalidDefinitionError{}} = Codec.encode(flow, wrong_registry)

    document = %{
      "type" => "jido.flow",
      "vsn" => 2,
      "name" => "one_subflow",
      "description" => nil,
      "schema" => %{"id" => "schemas/map", "vsn" => 1},
      "output_schema" => %{"id" => "schemas/map", "vsn" => 1},
      "components" => [
        %{
          "name" => "child",
          "needs" => [],
          "meta" => %{"$type" => "map", "entries" => []},
          "kind" => "call",
          "call" => %{
            "kind" => "flow",
            "target" => %{"id" => "targets/child", "vsn" => 1},
            "params" => %{"$type" => "map", "entries" => []}
          }
        }
      ],
      "output" => %{
        "$ref" => %{"source" => "result", "component" => "child", "path" => []}
      }
    }

    assert {:error, %InvalidDefinitionError{}} = Codec.decode(document, wrong_registry)
  end

  test "unknown module text is never resolved without a Registry entry" do
    {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), CodecRegistry.mixed())
    [step | rest] = document["components"]
    unknown_identifier = "untrusted/action/#{System.unique_integer([:positive])}"

    document = %{
      document
      | "components" => [
          JidoActionTest.StoredFields.update(step, %{
            "action" => %{"id" => unknown_identifier, "vsn" => 1}
          })
          | rest
        ]
    }

    refute existing_atom?(unknown_identifier)

    assert {:error, %InvalidDefinitionError{}} =
             Codec.decode(document, CodecRegistry.mixed())

    refute existing_atom?(unknown_identifier)
  end

  test "JSON bytes preserve string, integer, and registered atom map keys" do
    registry = CodecRegistry.storage()

    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "stored_key_types",
        components: [
          %{
            kind: :step,
            name: "keys",
            action: Add,
            params: %{
              "string-key" => "value",
              7 => [%{:atom_key => :ready}],
              :atom_key => %{9 => :ready}
            },
            meta: %{
              "owner" => %{1 => :ready, :atom_key => "meta"},
              "tags" => ["stored", "portable"]
            }
          }
        ],
        output: Ref.result("keys")
      })

    assert {:ok, document} = Codec.encode(flow, registry)

    assert {:ok, decoded} =
             document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)

    assert decoded == flow
    assert {:ok, ^document} = Codec.encode(decoded, registry)
  end

  test "JSON bytes preserve Boolean map keys" do
    registry = CodecRegistry.mixed()

    flow = %{
      FlowAuthoring.mixed_flow!()
      | name: "stored_boolean_keys",
        output: %{false => "no", true => "yes"}
    }

    assert {:ok, document} = Codec.encode(flow, registry)
    assert {:ok, ^flow} = document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)
  end

  test "reference records reject extra fields and report the exact path" do
    registry = CodecRegistry.mixed()
    flow = %{FlowAuthoring.mixed_flow!() | schema: Jido.Joi.object(%{})}
    assert {:ok, document} = Codec.encode(flow, registry)

    schema = Map.put(document["schema"], "extra", true)
    target_index = Enum.find_index(document["components"], &Map.has_key?(&1, "call"))

    target =
      document
      |> get_in(["components", Access.at(target_index), "call", "target"])
      |> Map.put("extra", true)

    cases = [
      {%{document | "schema" => schema}, ["schema", "extra"]},
      {put_in(document, ["components", Access.at(target_index), "call", "target"], target),
       ["components", target_index, "call", "target", "extra"]}
    ]

    for {invalid, path} <- cases do
      assert {:error, %Error.Invalid{errors: [error]}} = Codec.diagnose(invalid, registry)
      assert error.details.path == path
    end
  end

  test "invalid reference versions report the vsn field" do
    registry = CodecRegistry.mixed()
    flow = %{FlowAuthoring.mixed_flow!() | schema: Jido.Joi.object(%{})}
    assert {:ok, document} = Codec.encode(flow, registry)

    for invalid_vsn <- [0, "1", nil] do
      schema = Map.put(document["schema"], "vsn", invalid_vsn)

      assert {:error, %Error.Invalid{errors: [error]}} =
               Codec.diagnose(%{document | "schema" => schema}, registry)

      assert error.details.path == ["schema", "vsn"]
    end
  end

  test "Codec rejects values above its nesting and collection limits" do
    registry = CodecRegistry.mixed()
    flow = FlowAuthoring.mixed_flow!()
    assert {:ok, document} = Codec.encode(flow, registry)

    deep_output = Enum.reduce(1..102, 0, fn _index, nested -> [nested] end)
    wide_output = List.duplicate(0, 10_001)

    assert {:error,
            %InvalidDefinitionError{
              message: "stored Flow exceeds its nesting limit",
              details: %{maximum_depth: 100}
            }} = Codec.decode(%{document | "output" => deep_output}, registry)

    assert {:error,
            %InvalidDefinitionError{
              message: "stored Flow collection exceeds its size limit",
              details: %{maximum_size: 10_000}
            }} = Codec.decode(%{document | "output" => wide_output}, registry)

    deep_flow = %{flow | name: "deep_encode", output: deep_output}
    wide_flow = %{flow | name: "wide_encode", output: wide_output}

    assert {:error,
            %InvalidDefinitionError{
              message: "stored Flow exceeds its nesting limit",
              details: %{maximum_depth: 100}
            }} = Codec.encode(deep_flow, registry)

    assert {:error,
            %InvalidDefinitionError{
              message: "stored Flow collection exceeds its size limit",
              details: %{maximum_size: 10_000}
            }} = Codec.encode(wide_flow, registry)

    {component_name, component} = Enum.at(flow.components, 0)

    for {value, detail} <- [
          {deep_output, {:maximum_depth, 100}},
          {wide_output, {:maximum_size, 10_000}}
        ] do
      metadata_flow = %{
        flow
        | components: Map.put(flow.components, component_name, %{component | meta: %{"payload" => value}})
      }

      assert {:error, %InvalidDefinitionError{details: details}} =
               Codec.encode(metadata_flow, registry)

      assert Map.fetch!(details, elem(detail, 0)) == elem(detail, 1)
    end

    for count <- [10_000, 10_001] do
      output = Map.new(1..count, &{&1, 0})
      map_flow = %{flow | name: "map_limit", output: output}

      if count == 10_000 do
        assert {:ok, _document} = Codec.encode(map_flow, registry)
      else
        assert {:error,
                %InvalidDefinitionError{
                  message: "stored Flow collection exceeds its size limit",
                  details: %{maximum_size: 10_000}
                }} =
                 Codec.encode(map_flow, registry)
      end
    end

    assert {:error, %InvalidDefinitionError{message: "stored Flow collection exceeds its size limit"}} =
             Codec.decode(
               %{document | "components" => List.duplicate(hd(document["components"]), 10_001)},
               registry
             )

    choice_index = component_index(document, "route")
    choice = component(document, "route")

    assert {:error, %InvalidDefinitionError{message: "stored Flow collection exceeds its size limit"}} =
             Codec.decode(
               replace_component(document, choice_index, %{
                 choice
                 | "options" => List.duplicate(%{}, 10_001)
               }),
               registry
             )
  end

  test "Codec bounds total decode work across permitted collections" do
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(FlowAuthoring.mixed_flow!(), registry)

    large_but_locally_valid = List.duplicate(List.duplicate(0, 10_000), 11)

    assert {:error,
            %InvalidDefinitionError{
              message: "stored Flow exceeds its total node limit",
              details: %{maximum_nodes: 100_000}
            }} = Codec.decode(%{document | "output" => large_but_locally_valid}, registry)
  end

  test "nested conditions use one tagged JSON grammar" do
    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "nested_condition",
        components: [
          %{
            kind: :choice,
            name: "route",
            options: [
              %{
                name: "nested",
                condition:
                  Jido.Expr.new!(:and, [
                    Jido.Expr.new!(:==, [Ref.input(:kind), :go]),
                    Jido.Expr.new!(:not, [Jido.Expr.new!(:==, [Ref.input(:value), 0])])
                  ]),
                action: Add
              }
            ],
            fallback: %{action: Add}
          }
        ],
        output: Ref.result("route")
      })

    assert {:ok, document} = Codec.encode(flow, CodecRegistry.mixed())
    assert {:ok, ^flow} = Codec.decode(document, CodecRegistry.mixed())
  end

  test "the encoder reports a missing trusted action inside a Choice option" do
    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "unregistered_choice_action",
        components: [
          %{
            kind: :choice,
            name: "route",
            options: [
              %{
                name: "multiply",
                condition: Jido.Expr.new!(:==, [1, 1]),
                action: Multiply
              }
            ],
            fallback: %{action: Add}
          }
        ],
        output: Ref.result("route")
      })

    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"actions/add", 1} => {:action, Add},
        {"schemas/map", 1} => {:schema, Jido.Joi.map()}
      })

    assert {:error, %InvalidDefinitionError{}} = Codec.encode(flow, registry)
  end

  test "the decoder rejects malformed nested stored records" do
    assert {:ok, document} =
             Codec.encode(FlowAuthoring.mixed_flow!(), CodecRegistry.mixed())

    step_index = component_index(document, "load")
    choice_index = component_index(document, "route")
    iterate_index = component_index(document, "loop")
    step = component(document, "load")
    choice = component(document, "route")
    iterate = component(document, "loop")
    [option] = choice["options"]

    duplicate_map = %{
      "$type" => "map",
      "entries" => [
        %{"key" => "same", "value" => 1},
        %{"key" => "same", "value" => 2}
      ]
    }

    invalid_documents = [
      %{document | "components" => []},
      %{document | "components" => [nil]},
      replace_component(document, choice_index, %{choice | "options" => []}),
      replace_component(document, choice_index, %{choice | "options" => "invalid"}),
      replace_component(document, choice_index, %{choice | "options" => [nil]}),
      replace_component(
        document,
        choice_index,
        %{choice | "options" => [%{option | "condition" => "invalid"}]}
      ),
      replace_component(
        document,
        choice_index,
        %{
          choice
          | "options" => [
              %{
                option
                | "condition" => %{
                    "$expr" => %{"operator" => "and", "operands" => "invalid"}
                  }
              }
            ]
        }
      ),
      %{document | "output" => %{"$type" => "atom", "id" => 42}},
      %{document | "output" => %{"$type" => "atom", "id" => "atoms/missing"}},
      %{document | "output" => duplicate_map},
      %{
        document
        | "output" => %{
            "$type" => "map",
            "entries" => [nil]
          }
      },
      replace_component(
        document,
        step_index,
        JidoActionTest.StoredFields.update(step, %{"action" => 42})
      ),
      %{document | "description" => 42},
      replace_component(document, step_index, %{step | "needs" => 42}),
      replace_component(document, iterate_index, %{iterate | "max_iterations" => 0}),
      replace_component(document, iterate_index, %{iterate | "state" => 42}),
      replace_component(document, choice_index, %{choice | "fallback" => 42})
    ]

    for invalid <- invalid_documents do
      assert {:error, %InvalidDefinitionError{}} = Codec.decode(invalid, CodecRegistry.mixed())

      assert {:error, %Error.Invalid{errors: [_first | _rest]}} =
               Codec.diagnose(invalid, CodecRegistry.mixed())
    end
  end

  defp inline_probe_registry do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"actions/mark/v1", 1} => {:action, InlineProbeFlow.step_action("mark")},
      {"flows/not-an-action", 1} => {:flow, NestedFlow},
      {"atoms/marker", 1} => {:atom, :marker},
      {"schemas/map/v1", 1} => {:schema, Jido.Joi.map()}
    })
  end

  defp all_component_flow! do
    JidoActionTest.FlowBuilder.new!(%{
      name: "all_stored_components",
      components: [
        %{kind: :step, name: "step", action: Add},
        %{kind: :subflow, name: "subflow", flow: NestedFlow, needs: ["step"]},
        %{
          kind: :choice,
          name: "choice",
          options: [
            %{name: "yes", condition: Jido.Expr.new!(:==, [1, 1]), action: Add}
          ],
          fallback: %{action: Multiply},
          needs: ["step"]
        },
        %{kind: :map, name: "map", collection: [], action: Add, needs: ["step"]},
        %{
          kind: :parallel,
          name: "parallel",
          actions: [
            %{name: "add", action: Add},
            %{name: "multiply", action: Multiply}
          ],
          needs: ["step"]
        },
        %{
          kind: :reduce,
          name: "reduce",
          collection: [],
          initial: %{},
          action: Add,
          needs: ["step"]
        },
        %{
          kind: :iterate,
          name: "iterate",
          action: Add,
          state: %{initial: %{}, update: %{}},
          completion: Jido.Expr.new!(:==, [1, 1]),
          max_iterations: 1,
          needs: ["step"]
        },
        %{
          kind: :invoke,
          name: "invoke",
          decision: Add,
          expander: Add,
          needs: ["step", "subflow", "choice", "map", "parallel", "reduce", "iterate"]
        }
      ],
      output: Ref.result("invoke")
    })
  end

  defp replace_component(document, index, component) do
    %{document | "components" => List.replace_at(document["components"], index, component)}
  end

  defp replace_named_component(document, name, replacement) do
    replace_component(document, component_index(document, name), replacement)
  end

  defp component(document, name) do
    Enum.find(document["components"], &(&1["name"] == name))
  end

  defp component_index(document, name) do
    Enum.find_index(document["components"], &(&1["name"] == name))
  end

  defp existing_atom?(value) do
    _atom = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
