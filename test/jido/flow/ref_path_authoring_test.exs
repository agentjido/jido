defmodule Jido.Flow.RefPathAuthoringTest.ValidFlow do
  @moduledoc false
  use Jido.Flow, name: "reference_paths"

  flow do
    step("echo",
      action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
      params: %{
        input: input([]),
        selected: input([:payload, "項目🌿", 0]),
        context: context(:optional),
        literal: nil
      }
    )

    output(%{echo: result("echo"), selected: select(result("echo"), :selected)})
  end
end

defmodule Jido.Flow.RefPathAuthoringTest do
  use ExUnit.Case, async: true
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Error.ValidationError
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  defmodule CountedAction do
    use Jido.Action, name: "counted_reference_action"

    def run(params, %{calls: calls}) do
      Agent.update(calls, &(&1 + 1))
      {:ok, params}
    end
  end

  test "all authoring forms preserve supported paths and present nil values" do
    params = %{
      input: Ref.input([]),
      selected: Ref.input([:payload, "項目🌿", 0]),
      context: Ref.context(:optional),
      literal: nil
    }

    output = %{echo: Ref.result("echo"), selected: Ref.result("echo", :selected)}

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: "reference_paths",
        components: [
          JidoActionTest.FlowComponent.step!(
            name: "echo",
            action: EchoParamsAction,
            params: params
          )
        ],
        output: output
      )

    assert {:ok, built} =
             JidoActionTest.FlowBuilder.new(%{
               output: output,
               components: [
                 %{kind: :step, name: "echo", action: EchoParamsAction, params: params}
               ],
               name: "reference_paths"
             })

    assert {:ok, document, registry} = Codec.encode(direct)

    assert {:ok, decoded} =
             document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)

    input = %{payload: %{"項目🌿" => [nil]}}
    expected = %{echo: %{input: input, selected: nil, context: nil, literal: nil}, selected: nil}

    for flow <- [direct, built, decoded, __MODULE__.ValidFlow.flow()] do
      assert flow == direct
      assert Jido.Exec.run(flow, input, %{optional: nil}) == {:ok, expected}

      assert {:error,
              %Jido.Error.ExecutionError{
                details: %{reason: :missing_index, path: [:payload, "項目🌿", 0]}
              }} = Jido.Exec.run(flow, %{payload: %{"項目🌿" => []}}, %{optional: nil})
    end
  end

  test "atom paths prefer present atom keys, including nil and false, before string keys" do
    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "key_precedence",
        components: [
          JidoActionTest.FlowComponent.step!(
            name: "echo",
            action: EchoParamsAction,
            params: %{value: Ref.input(:value)}
          )
        ],
        output: Ref.result("echo")
      )

    for value <- [nil, false, 7] do
      assert Jido.Exec.run(flow, %{:value => value, "value" => 42}) == {:ok, %{value: value}}
    end

    assert Jido.Exec.run(flow, %{"value" => 42}) == {:ok, %{value: 42}}
    assert {:error, %{details: %{reason: :missing_key}}} = Jido.Exec.run(flow, %{})
  end

  test "Flow, and Codec reject malformed reference paths" do
    step = JidoActionTest.FlowComponent.step!(name: "echo", action: EchoParamsAction)

    valid =
      JidoActionTest.FlowBuilder.new!(
        name: "invalid_paths",
        components: [step],
        output: Ref.input([])
      )

    assert {:ok, document, registry} = Codec.encode(valid)

    for path <- [
          [nil],
          ["value", nil, 0],
          ["value", nil],
          ["value" | :tail],
          [-1],
          [1.5],
          [<<255>>]
        ] do
      ref = Ref.input(path)

      assert {:error, %ValidationError{}} =
               JidoActionTest.FlowBuilder.new(
                 name: "invalid_paths",
                 components: [step],
                 output: %{nested: [ref]}
               )

      assert {:error, %ValidationError{}} =
               JidoActionTest.FlowBuilder.new(%{
                 output: Jido.Flow.Ref.result("echo"),
                 components: [
                   %{
                     kind: :step,
                     name: "echo",
                     action: EchoParamsAction,
                     params: %{nested: [Jido.Flow.Ref.input(path)]}
                   }
                 ],
                 name: "invalid_paths"
               })

      assert {:error, %ValidationError{}} =
               JidoActionTest.FlowBuilder.new(%{
                 output: %{nested: [Jido.Flow.Ref.select(Jido.Flow.Ref.input([]), path)]},
                 components: [%{kind: :step, name: "echo", action: EchoParamsAction, params: %{}}],
                 name: "invalid_paths"
               })

      invalid_flow = %{valid | output: ref}
      assert {:error, %ValidationError{}} = Codec.encode(invalid_flow, registry)
      stored_ref = %{"$ref" => %{"source" => "input", "component" => nil, "path" => path}}

      assert {:error, %ValidationError{}} =
               Codec.decode(%{document | "output" => stored_ref}, registry)
    end
  end

  test "direct construction and map authoring reject invalid UTF-8 with expression paths" do
    segment = <<255>>
    ref = Ref.input([segment])
    params = %{nested: [ref]}

    assert {:error,
            %ValidationError{
              message: "flow expression contains an invalid reference path",
              details: %{path: [:nested, 0], segment: ^segment}
            }} = Jido.Flow.Value.validate(params)

    assert {:error,
            %ValidationError{
              details: %{path: [:call, :params, :nested, 0], segment: ^segment}
            }} =
             JidoActionTest.FlowComponent.step(
               name: "echo",
               action: EchoParamsAction,
               params: params
             )

    assert {:error, %ValidationError{details: %{path: [:output, :nested, 0], segment: ^segment}}} =
             JidoActionTest.FlowBuilder.new(
               name: "utf8_paths",
               components: [
                 JidoActionTest.FlowComponent.step!(name: "echo", action: EchoParamsAction)
               ],
               output: params
             )

    assert {:error,
            %ValidationError{
              details: %{path: [:components, 0, :call, :params, :nested, 0], segment: ^segment}
            }} =
             JidoActionTest.FlowBuilder.new(%{
               output: Jido.Flow.Ref.result("echo"),
               components: [
                 %{kind: :step, name: "echo", action: EchoParamsAction, params: params}
               ],
               name: "utf8_paths"
             })
  end

  test "Codec rejects invalid UTF-8 reference paths before returning a stored document" do
    segment = <<255>>

    step =
      JidoActionTest.FlowComponent.step!(
        name: "echo",
        action: EchoParamsAction,
        params: Ref.input([])
      )

    valid = JidoActionTest.FlowBuilder.new!(name: "utf8_paths", components: [step], output: %{})
    assert {:ok, document, registry} = Codec.encode(valid)
    node = valid.components["echo"]
    instruction = node.call

    invalid = %{
      valid
      | components:
          Map.put(valid.components, "echo", %{
            node
            | call: Map.put(instruction, :params, Ref.input([segment]))
          })
    }

    for result <- [Codec.encode(invalid, registry), Codec.encode(invalid)] do
      assert {:error,
              %ValidationError{
                message: "flow expression contains an invalid reference path",
                details: %{path: [:components, "echo", :call, :params], segment: ^segment}
              }} = result
    end

    [stored_step] = document["components"]
    stored_step = put_in(stored_step, ["call", "params", "$ref", "path"], [segment])
    invalid_document = %{document | "components" => [stored_step]}

    assert {:error,
            %ValidationError{
              message: "flow expression contains an invalid reference path",
              details: %{path: ["components", 0, "call", "params"], segment: ^segment}
            }} = Codec.decode(invalid_document, registry)
  end

  test "Ref.select rejects an invalid source with a structured error" do
    for path <- [[:payload | :tail], [:payload, :value | nil], [nil], nil, :payload, 0, %{}] do
      source = %Ref{source: :input, path: path}

      error =
        assert_raise ValidationError, "invalid flow ref", fn ->
          Jido.Flow.Ref.select(
            source,
            :value
          )
        end

      assert error.details.reason == :path
      assert error.details.ref == source
    end
  end

  test "Ref.select preserves valid global and local reference sources" do
    for source <- [
          Ref.input([]),
          Ref.context(),
          Ref.result("echo"),
          Ref.item(),
          Ref.accumulator(),
          Ref.state(),
          Ref.body_result()
        ] do
      assert Jido.Flow.Ref.select(source, [:payload, "項目🌿", 0]) == %{
               source
               | path: [:payload, "項目🌿", 0]
             }

      assert Jido.Flow.Ref.select(source, nil) == source
    end

    for source <- [Ref.item_index(), Ref.item_id(), Ref.iteration_index()] do
      assert Jido.Flow.Ref.select(source, []) == source
    end
  end

  test "Exec rejects invalid paths for every source before any Action work" do
    calls = start_supervised!({Agent, fn -> 0 end})
    first = JidoActionTest.FlowComponent.step!(name: "first", action: CountedAction)

    components =
      for ref <- [Ref.input([]), Ref.context(), Ref.result("first")] do
        JidoActionTest.FlowComponent.step!(
          name: "node",
          action: EchoParamsAction,
          params: %{value: ref}
        )
      end

    components =
      components ++
        for ref <- [Ref.item(), Ref.item_index(), Ref.item_id()] do
          JidoActionTest.FlowComponent.map!(
            name: "node",
            action: EchoParamsAction,
            collection: [],
            params: %{value: ref}
          )
        end

    components =
      components ++
        [
          JidoActionTest.FlowComponent.reduce!(
            name: "node",
            action: EchoParamsAction,
            collection: [],
            initial: %{},
            params: %{value: Ref.accumulator()}
          )
        ] ++
        for ref <- [Ref.state(), Ref.iteration_index()] do
          JidoActionTest.FlowComponent.iterate!(
            name: "node",
            action: EchoParamsAction,
            params: %{value: ref},
            state: [schema: Jido.Joi.map(), initial: %{}, update: %{}],
            completion: true,
            max_iterations: 1
          )
        end

    for component <- components do
      flow =
        Flow.new!(%{
          name: "invalid_paths",
          components: [first, component],
          output: Ref.result("node")
        })

      for path <- [[nil], [:value, nil, 0], [:value, nil], [:value | :tail], [-1], [0.0]] do
        invalid = put_in(flow.components["node"].call.params.value.path, path)

        assert {:error, %ValidationError{} = error} =
                 Jido.Exec.run(invalid, %{}, %{calls: calls})

        assert error.details.path == [:components, "node", :call, :params, :value]
      end
    end

    iterate =
      JidoActionTest.FlowComponent.iterate!(
        name: "node",
        action: EchoParamsAction,
        state: [schema: Jido.Joi.map(), initial: %{}, update: %{value: Ref.body_result()}],
        completion: true,
        max_iterations: 1
      )

    flow =
      Flow.new!(%{
        name: "invalid_update",
        components: [first, iterate],
        output: Ref.result("node")
      })

    invalid = put_in(flow.components["node"].state.update.value.path, [nil])

    assert {:error, %ValidationError{} = error} =
             Jido.Exec.run(invalid, %{}, %{calls: calls})

    assert error.details.path == [:components, "node", :state, :update, :value]
    assert Agent.get(calls, & &1) == 0
    assert {:ok, %{}} = Jido.Exec.run(CountedAction, %{}, %{calls: calls})
    assert Agent.get(calls, & &1) == 1
  end

  test "the module DSL rejects nil segments and malformed paths before execution" do
    for {path, index} <-
          Enum.with_index([
            "[nil]",
            "[nil, :value]",
            "[:value, nil, 0]",
            "[:value, nil]",
            "[:value | :tail]",
            "[-1]",
            "[%{}]",
            "[<<255>>]"
          ]) do
      code = "defmodule #{__MODULE__}.Invalid#{index} do
  use Jido.Flow, name: \"invalid_reference_path\"

  flow do
    step \"echo\",
      action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
      params: %{nested: [input(#{path})]}

    output(result(\"echo\"))
  end
end
"

      assert_raise CompileError, ~r/invalid reference path|unsupported Flow expression/, fn ->
        Code.compile_string(code)
      end
    end
  end
end
