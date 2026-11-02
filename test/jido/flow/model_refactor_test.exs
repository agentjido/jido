defmodule Jido.Flow.ModelRefactorTest do
  use ExUnit.Case, async: true

  alias Jido.{Exec, Expr, Flow}
  alias Jido.Flow.{Codec, Definition, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Fixtures.Actions.{Add, EchoParamsAction}

  test "compact data authoring produces an internal call record" do
    component = %{
      name: "add",
      kind: :step,
      action: Add,
      params: %{value: Ref.input(:value), amount: 1},
      needs: [],
      meta: %{}
    }

    flow = Flow.new!(%{name: "common_call", components: [component], output: Ref.result("add")})

    assert flow.components["add"] == %{
             kind: :call,
             call: %{kind: :action, target: Add, params: component.params},
             needs: [],
             meta: %{}
           }

    assert Flow.validate(flow) == {:ok, flow}
    assert Exec.run(flow, %{value: 2}) == {:ok, %{value: 3}}
    assert Flow.to_map(flow).components == [Map.put(flow.components["add"], :name, "add")]
  end

  test "one stored version supports expressions and the common component fields" do
    flow =
      Flow.new!(%{
        name: "common_document",
        components: [
          %{
            name: "echo",
            kind: :step,
            action: EchoParamsAction,
            params: %{value: Expr.new!(:+, [Ref.input(:value), 1])}
          }
        ],
        output: Ref.result("echo")
      })

    assert {:ok, document, registry} = Codec.encode(flow)
    assert document["vsn"] == 2

    assert [%{"kind" => "call", "call" => %{"kind" => "action", "target" => _, "params" => _}}] =
             document["components"]

    assert Codec.decode(document, registry) == {:ok, flow}
    assert {:error, _} = Codec.decode(%{document | "vsn" => 3}, registry)
  end

  test "data and JSON use the same ordered graph diagnostics" do
    attrs = %{
      name: "common_errors",
      components: [
        %{
          name: "echo",
          kind: :step,
          action: EchoParamsAction,
          needs: ["z_missing", "a_missing"]
        }
      ],
      output: nil
    }

    valid =
      Flow.new!(%{
        attrs
        | components: [
            %{name: "echo", kind: :step, action: EchoParamsAction}
          ],
          output: %{}
      })

    assert {:ok, document, registry} = Codec.encode(valid)
    [component] = document["components"]

    invalid = %{
      document
      | "components" => [%{component | "needs" => ["z_missing", "a_missing"]}],
        "output" => nil
    }

    assert {:error, issues} = Definition.diagnose(attrs)
    assert {:error, %{errors: errors}} = Codec.diagnose(invalid, registry)
    assert Enum.map(issues, & &1.error.message) == Enum.map(errors, & &1.message)
    assert {:error, data_error} = Flow.new(attrs)
    assert {:error, json_error} = Codec.decode(invalid, registry)
    assert data_error.message == json_error.message
    assert Enum.map(errors, &Map.get(&1.details, :component)) == [nil, "z_missing", "a_missing"]
  end

  test "Invoke expanders have only a target record" do
    flow =
      Flow.new!(%{
        name: "target_only",
        components: [
          %{
            name: "next",
            kind: :invoke,
            decision: EchoParamsAction,
            expander: EchoParamsAction
          }
        ],
        output: Ref.result("next")
      })

    assert flow.components["next"].expander == %{kind: :action, target: EchoParamsAction}
    assert {:ok, document, registry} = Codec.encode(flow)
    assert Codec.decode(document, registry) == {:ok, flow}
  end

  test "canonical validation rejects fields that require authoring normalization" do
    flow =
      Flow.new!(%{
        name: "canonical_fields",
        components: [
          %{name: "echo", kind: :step, action: EchoParamsAction}
        ],
        output: %{}
      })

    node = flow.components["echo"]

    for {invalid, expected_path} <- [
          {Map.put(node, :name, "echo"), [:components, "echo", :name]},
          {put_in(node, [:call, :params], nil), [:components, "echo", :call, :params]}
        ] do
      assert {:error, error} = Flow.validate(%{flow | components: %{"echo" => invalid}})
      assert error.details.path == expected_path
    end
  end

  test "data and JSON keep the same nested field validation order" do
    attrs = %{
      name: "nested_errors",
      components: [
        %{
          name: "route",
          kind: :choice,
          options: [%{name: "yes", condition: true, action: Add, params: %{}}],
          fallback: %{action: Add}
        },
        %{
          name: "loop",
          kind: :iterate,
          action: Add,
          state: %{initial: %{}, update: %{}},
          completion: true,
          max_iterations: 1
        }
      ],
      output: %{}
    }

    flow = Flow.new!(attrs)
    assert {:ok, document, registry} = Codec.encode(flow)
    components = Enum.sort_by(attrs.components, & &1.name)
    [loop, route] = components
    [stored_loop, stored_route] = document["components"]

    invalid_loop = %{loop | completion: 123, max_iterations: 0}
    invalid_loop = put_in(invalid_loop, [:state, :initial], Ref.body_result())
    invalid_route = put_in(route, [:options, Access.at(0), :condition], 123)
    invalid_route = put_in(invalid_route, [:options, Access.at(0), :params], Ref.state())

    stored_loop =
      put_in(stored_loop, ["state", "initial"], %{
        "$ref" => %{"source" => "body_result", "component" => nil, "path" => []}
      })

    stored_loop = %{stored_loop | "completion" => 123, "max_iterations" => 0}
    stored_route = put_in(stored_route, ["options", Access.at(0), "condition"], 123)

    stored_route =
      put_in(stored_route, ["options", Access.at(0), "call", "params"], %{
        "$ref" => %{"source" => "state", "component" => nil, "path" => []}
      })

    assert {:error, issues} =
             Definition.diagnose(%{attrs | components: [invalid_loop, invalid_route]})

    assert {:error, %{errors: errors}} =
             Codec.diagnose(%{document | "components" => [stored_loop, stored_route]}, registry)

    assert Enum.map(issues, & &1.error.message) == Enum.map(errors, & &1.message)

    assert Enum.map(issues, & &1.location) == [
             [:components, 0, :state, :initial],
             [:components, 0, :completion],
             [:components, 0, :max_iterations],
             [:components, 1, :options, 0, :condition],
             [:components, 1, :options, 0, :call, :params]
           ]

    assert Enum.map(errors, & &1.details.path) ==
             Enum.map(issues, fn issue ->
               Enum.map(issue.location, fn segment ->
                 if is_atom(segment), do: Atom.to_string(segment), else: segment
               end)
             end)
  end

  test "wire failures keep their field position beside semantic failures" do
    flow =
      Flow.new!(%{
        name: "mixed_failures",
        components: [
          %{name: "echo", kind: :step, action: EchoParamsAction}
        ],
        output: %{}
      })

    assert {:ok, document, registry} = Codec.encode(flow)
    [component] = document["components"]
    component = %{component | "name" => nil, "needs" => 12, "meta" => %{"$type" => "unknown"}}
    component = put_in(component, ["call", "target"], "actions/missing")

    component =
      put_in(component, ["call", "params"], %{
        "$ref" => %{"source" => "state", "component" => nil, "path" => []}
      })

    assert {:error, %{errors: errors}} =
             Codec.diagnose(%{document | "components" => [component]}, registry)

    assert Enum.map(errors, & &1.details.path) == [
             ["components", 0, "name"],
             ["components", 0, "needs"],
             ["components", 0, "meta"],
             ["components", 0, "call", "target"],
             ["components", 0, "call", "params"]
           ]

    refute Enum.any?(errors, &Map.has_key?(&1.details, :source_path))
  end

  test "unknown stored target kinds have their own paths and create no atoms" do
    flow =
      Flow.new!(%{
        name: "unknown_kind",
        components: [
          %{name: "echo", kind: :step, action: EchoParamsAction}
        ],
        output: %{}
      })

    assert {:ok, document, registry} = Codec.encode(flow)
    unknown = "unknown_kind_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    for path <- [["kind"], ["call", "kind"]] do
      [component] = document["components"]
      invalid = put_in(component, path, unknown)
      assert {:error, error} = Codec.decode(%{document | "components" => [invalid]}, registry)
      assert error.details.path == ["components", 0] ++ path
      assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
    end
  end

  test "canonical component entries must be plain records" do
    flow =
      Flow.new!(%{
        name: "plain_nodes",
        components: [
          %{name: "echo", kind: :step, action: EchoParamsAction}
        ],
        output: %{}
      })

    for node <- [nil, :invalid, %Jido.Instruction{kind: :action, target: EchoParamsAction}] do
      assert {:error, error} = Flow.validate(%{flow | components: %{"echo" => node}})
      assert error.details.path == [:components, "echo"]
    end
  end

  test "stored atom keys cannot overwrite converted record fields" do
    flow =
      Flow.new!(%{
        name: "stored_keys",
        components: [
          %{name: "echo", kind: :step, action: EchoParamsAction}
        ],
        output: %{}
      })

    assert {:ok, document, registry} = Codec.encode(flow)

    for {path, key} <- [
          {[], :name},
          {["components", Access.at(0)], :name},
          {["components", Access.at(0)], :kind},
          {["components", Access.at(0), "call"], :target},
          {["components", Access.at(0), "call"], :kind}
        ] do
      invalid =
        if path == [],
          do: Map.put(document, key, :ignored),
          else: update_in(document, path, &Map.put(&1, key, :ignored))

      assert {:error, error} = Codec.decode(invalid, registry)
      assert error.details.key == key
    end
  end
end
