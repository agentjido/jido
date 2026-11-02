defmodule Jido.Flow.CanonicalDefinitionTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Flow.Codec
  alias Jido.Flow.Ref
  alias Jido.Authoring.Registry

  defmodule Echo do
    use Jido.Action, name: "canonical_flow_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Authored do
    use Jido.Flow, name: "canonical_authored_flow"

    flow do
      step("load", action: Echo, params: %{})
      step("save", action: Echo, params: %{value: result("load")})
      output(result("save"))
    end
  end

  defmodule PolicyAuthored do
    use Jido.Flow, name: "canonical_policy_flow"

    @llm_policy [
      timeout_ms: 5_000,
      retry: [
        max_attempts: 3,
        backoff: :exponential,
        base_delay_ms: 250,
        max_delay_ms: 1_000
      ]
    ]

    flow do
      step("work",
        action: Echo,
        params: %{value: input(:value)},
        policy: @llm_policy
      )

      output(result("work"))
    end
  end

  defmodule OutcomeAuthored do
    use Jido.Flow, name: "canonical_outcome_flow"

    flow do
      step("work",
        action: Echo,
        params: %{value: input(:value)},
        on_error: :collect_errors
      )

      output(result("work"))
    end
  end

  defmodule Mapped do
    use Jido.Flow, name: "canonical_mapped_flow"

    flow do
      step("load", action: Echo, params: %{items: input(:items)})

      map("echo_each",
        collection: result("load", :items),
        action: Echo,
        params: %{index: item_index(), value: item()},
        timeout_ms: 500,
        retry: [max_attempts: 2]
      )

      output(result("echo_each"))
    end
  end

  test "stores canonical definition data with derived graph and identity" do
    flow =
      Flow.new!(%{
        name: "canonical",
        forms: %{
          load: Echo,
          save: {Echo, %{value: Ref.result(:load)}}
        },
        needs: %{save: [:load]},
        output: Ref.result(:save)
      })

    assert %Flow{forms: %{"load" => _, "save" => _}} = flow
    assert flow.needs == %{"save" => ["load"]}
    assert %Jido.Flow.Graph{} = flow.graph
    assert is_map(flow.identity)
    refute Map.has_key?(flow, :compiled)
    refute Map.has_key?(flow, :dependencies)
    refute Map.has_key?(flow, :execution_state)
    refute Map.has_key?(flow, :components)

    assert {:ok,
            %{
              "load" => %{data: [], control: []},
              "save" => %{data: ["load"], control: []}
            }} = Flow.dependencies(flow)

    assert {:ok, ^flow} = Flow.validate(flow)
  end

  test "Flow modules do not define an execution pass-through" do
    refute function_exported?(Authored, :run, 2)
  end

  test "DSL, map, and JSON authoring produce the same canonical Flow" do
    from_dsl = Authored.flow()

    from_map =
      Flow.new!(%{
        name: "canonical_authored_flow",
        forms: %{
          "load" => Echo,
          "save" => {Echo, %{value: Ref.result("load")}}
        },
        output: Ref.result("save")
      })

    registry =
      Registry.new!(%{
        {"actions/echo", 1} => {:action, Echo},
        {"atoms/value", 1} => {:atom, :value},
        {"schemas/empty", 1} => {:schema, []}
      })

    assert {:ok, json} =
             Jido.Authoring.encode_json(from_map, registry: registry, codec: Codec)

    assert {:ok, from_json} =
             Jido.Authoring.decode_json(json, registry: registry, codec: Codec)

    assert from_dsl == from_map
    assert from_json == from_map
    assert Flow.semantic_identity(from_dsl) == Flow.semantic_identity(from_json)
  end

  test "DSL, map, and JSON keep one canonical call policy" do
    policy = %{
      timeout_ms: 5_000,
      retry: %{
        max_attempts: 3,
        backoff: :exponential,
        base_delay_ms: 250,
        max_delay_ms: 1_000
      }
    }

    from_dsl = PolicyAuthored.flow()

    from_map =
      Flow.new!(%{
        name: "canonical_policy_flow",
        forms: %{
          "work" => %{
            type: :call,
            action: Echo,
            params: %{value: Ref.input(:value)},
            policy: policy
          }
        },
        output: Ref.result("work")
      })

    registry =
      Registry.new!(%{
        {"actions/echo", 1} => {:action, Echo},
        {"atoms/value", 1} => {:atom, :value},
        {"schemas/empty", 1} => {:schema, []}
      })

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert from_map.forms["work"].policy == policy
    assert Flow.semantic_identity(from_dsl) == Flow.semantic_identity(from_json)
  end

  test "DSL, map, and JSON keep one canonical call outcome policy" do
    from_dsl = OutcomeAuthored.flow()

    from_map =
      Flow.new!(%{
        name: "canonical_outcome_flow",
        forms: %{
          "work" => %{
            type: :call,
            action: Echo,
            params: %{value: Ref.input(:value)},
            on_error: :collect_errors
          }
        },
        output: Ref.result("work")
      })

    registry =
      Registry.new!(%{
        {"actions/echo", 1} => {:action, Echo},
        {"atoms/value", 1} => {:atom, :value},
        {"schemas/empty", 1} => {:schema, []}
      })

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert from_map.forms["work"].on_error == :collect_errors
    assert Flow.semantic_identity(from_dsl) == Flow.semantic_identity(from_json)
  end

  test "call outcome policy changes semantic identity" do
    build = fn on_error ->
      Flow.new!(%{
        name: "outcome_identity",
        forms: %{
          work: %{type: :call, action: Echo, on_error: on_error}
        },
        output: Ref.result(:work)
      })
    end

    refute Flow.semantic_identity(build.(:fail_fast)) ==
             Flow.semantic_identity(build.(:collect_errors))
  end

  test "call policy changes semantic identity but caller metadata does not" do
    build = fn timeout_ms, trace ->
      Flow.new!(%{
        name: "policy_identity",
        forms: %{
          work: %{
            type: :call,
            action: Echo,
            metadata: %{trace: trace},
            policy: %{timeout_ms: timeout_ms}
          }
        },
        output: Ref.result(:work)
      })
    end

    first = build.(100, "first")
    same_policy = build.(100, "second")
    changed_policy = build.(200, "first")

    assert Flow.semantic_identity(first) == Flow.semantic_identity(same_policy)
    refute Flow.semantic_identity(first) == Flow.semantic_identity(changed_policy)
  end

  test "rejects an invalid call policy" do
    assert {:error, error} =
             Flow.new(%{
               name: "invalid_policy",
               forms: %{
                 work: %{
                   type: :call,
                   action: Echo,
                   policy: %{retry: %{max_attempts: 0, delay_ms: -1}}
                 }
               },
               output: Ref.result(:work)
             })

    assert error.details.reason == :invalid_call_policy
  end

  test "selects validation errors in stable field order" do
    build = fn fields ->
      form = Map.new([{:type, :call}, {:action, Echo} | fields])

      Flow.new(%{
        name: "stable_validation_error",
        forms: %{work: form},
        output: Ref.result(:work)
      })
    end

    assert {:error, first} = build.([{:zeta, true}, {:alpha, true}])
    assert {:error, second} = build.([{:alpha, true}, {:zeta, true}])
    assert first.details.field == :alpha
    assert second.details == first.details
  end

  test "rejects a complete policy mixed with policy shorthands" do
    assert {:error, error} =
             Flow.new(%{
               name: "mixed_policy",
               forms: %{
                 work: %{
                   type: :call,
                   action: Echo,
                   policy: %{timeout_ms: 100},
                   timeout_ms: 200
                 }
               },
               output: Ref.result(:work)
             })

    assert error.details.reason == :invalid_call_policy
    assert error.details.field == :mixed_policy_fields
  end

  test "rejects call policy on a child Flow target" do
    assert {:error, error} =
             Flow.new(%{
               name: "invalid_child_policy",
               forms: %{
                 work: %{type: :call, action: Authored, timeout_ms: 100}
               },
               output: Ref.result(:work)
             })

    assert error.details.reason == :unsupported_flow_call_policy
  end

  test "DSL, map, and JSON authoring produce the same canonical Map form" do
    from_dsl = Mapped.flow()

    from_map =
      Flow.new!(%{
        name: "canonical_mapped_flow",
        forms: %{
          "load" => {Echo, %{items: Ref.input(:items)}},
          "echo_each" => %{
            type: :map,
            collection: Ref.result("load", :items),
            action: Echo,
            params: %{index: Ref.item_index(), value: Ref.item()},
            timeout_ms: 500,
            retry: [max_attempts: 2]
          }
        },
        output: Ref.result("echo_each")
      })

    registry =
      Registry.new!(%{
        {"actions/echo", 1} => {:action, Echo},
        {"atoms/items", 1} => {:atom, :items},
        {"atoms/index", 1} => {:atom, :index},
        {"atoms/value", 1} => {:atom, :value},
        {"schemas/empty", 1} => {:schema, []}
      })

    assert {:ok, document} = Codec.encode_document(from_map, registry)
    assert {:ok, from_json} = Codec.decode_document(document, registry)

    assert from_dsl == from_map
    assert from_json == from_map
    assert %Jido.Flow.Form.Map{} = from_map.forms["echo_each"]

    assert from_map.forms["echo_each"].call.policy == %{
             timeout_ms: 500,
             retry: %{
               max_attempts: 2,
               backoff: :none,
               base_delay_ms: 0,
               max_delay_ms: 0
             }
           }

    assert from_dsl.graph == from_map.graph
    assert from_json.graph == from_map.graph
  end

  test "map order and DSL source order do not add dependencies" do
    independent =
      Flow.new!(%{
        name: "independent",
        forms: %{"second" => Echo, "first" => Echo},
        output: Ref.result("second")
      })

    assert {:ok,
            %{
              "first" => %{data: [], control: []},
              "second" => %{data: [], control: []}
            }} = Flow.dependencies(independent)

    assert {:ok, dependencies} = Flow.dependencies(Authored.flow())
    assert dependencies["save"].data == ["load"]
    assert dependencies["save"].control == []
  end

  test "keeps item references inside Map bodies" do
    assert {:error, error} =
             Flow.new(%{
               name: "invalid_item_scope",
               forms: %{one: {Echo, %{value: Ref.item()}}},
               output: Ref.result(:one)
             })

    assert error.details.ref_type == :item
    assert error.details.scope == :flow

    assert {:error, index_error} =
             Flow.new(%{
               name: "invalid_item_index_scope",
               forms: %{one: {Echo, %{value: Ref.item_index()}}},
               output: Ref.result(:one)
             })

    assert index_error.details.ref_type == :item_index
    assert index_error.details.scope == :flow

    assert_raise Jido.Flow.Error.InvalidDefinitionError, fn ->
      Ref.select(Ref.item_index(), :value)
    end
  end

  test "uses collection as the only Map collection field" do
    assert {:error, error} =
             Flow.new(%{
               name: "old_map_field",
               forms: %{
                 each: %{
                   type: :map,
                   over: Ref.input(:items),
                   action: Echo,
                   params: %{value: Ref.item()}
                 }
               },
               output: Ref.result(:each)
             })

    assert error.details.reason == :unknown_field
    assert error.details.field == :over
  end

  test "does not inspect a Map target when the Flow is validated" do
    flow =
      Flow.new!(%{
        name: "map_flow_body",
        forms: %{
          each: %{
            type: :map,
            collection: Ref.input(:items),
            action: MissingMapAction,
            params: %{value: Ref.item()}
          }
        },
        output: Ref.result(:each)
      })

    assert {:ok, ^flow} = Flow.validate(flow)
  end

  test "semantic identity excludes caller metadata" do
    first =
      Flow.new!(%{
        name: "metadata_identity",
        forms: %{work: {Echo, %{}, %{}, %{trace: "first"}}},
        output: Ref.result(:work)
      })

    second =
      Flow.new!(%{
        name: "metadata_identity",
        forms: %{work: {Echo, %{}, %{}, %{trace: "second"}}},
        output: Ref.result(:work)
      })

    refute first == second
    assert Flow.semantic_identity(first) == Flow.semantic_identity(second)
    assert Flow.semantic_identity(first) == Flow.semantic_identity(second)
  end

  test "rejects unknown dependencies and cycles" do
    assert {:error, unknown} =
             Flow.new(%{
               name: "unknown",
               forms: %{one: Echo},
               needs: %{one: [:missing]},
               output: Ref.result(:one)
             })

    assert unknown.details.reason == :unknown_dependency

    assert {:error, cycle} =
             Flow.new(%{
               name: "cycle",
               forms: %{one: Echo, two: Echo},
               needs: %{one: [:two], two: [:one]},
               output: Ref.result(:one)
             })

    assert cycle.details.reason == :cycle
  end

  test "requires an explicit known output" do
    assert {:error, required} = Flow.new(%{name: "missing_output", forms: %{one: Echo}})
    assert required.details.reason == :output_required

    assert {:error, unknown} =
             Flow.new(%{
               name: "unknown_output",
               forms: %{one: Echo},
               output: Ref.result(:missing)
             })

    assert unknown.details.reason == :unknown_output_reference
  end
end
