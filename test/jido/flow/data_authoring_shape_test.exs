defmodule Jido.Flow.DataAuthoringShapeTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.Error.InvalidDefinitionError
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction
  alias JidoActionTest.Fixtures.NestedFlow

  test "compact definitions produce valid canonical artifacts and one stored format" do
    for component <- components() do
      flow = Flow.new!(definition(component))
      assert Flow.validate(flow) == {:ok, flow}
      assert {:ok, document, registry} = Codec.encode(flow)
      assert document["vsn"] == 2
      assert Codec.decode(document, registry) == {:ok, flow}
    end
  end

  test "canonical component records are rejected as data authoring input" do
    for component <- components() do
      flow = Flow.new!(definition(component))
      internal = Map.put(flow.components[component.name], :name, component.name)

      assert {:error, %InvalidDefinitionError{} = error} = Flow.new(definition(internal))
      assert [:components, 0 | _] = error.details.path
      assert_raise InvalidDefinitionError, fn -> Flow.new!(definition(internal)) end
    end
  end

  test "mixed compact and internal fields are rejected instead of discarded" do
    for component <- components(),
        Map.has_key?(component, :action) or
          Map.has_key?(component, :flow) do
      flow = Flow.new!(definition(component))
      mixed = Map.put(component, :call, flow.components[component.name].call)

      assert {:error, %InvalidDefinitionError{} = error} = Flow.new(definition(mixed))
      assert error.details.path == [:components, 0, :call]
    end

    choice = Enum.find(components(), &(&1.kind == :choice))
    [option] = choice.options
    call = %{kind: :action, target: EchoParamsAction, params: %{}}

    for {invalid, path} <- [
          {%{choice | options: [Map.put(option, :call, call)]}, [:options, 0, :call]},
          {%{choice | fallback: Map.merge(choice.fallback, call)}, [:fallback, :kind]}
        ] do
      assert {:error, %InvalidDefinitionError{} = error} = Flow.new(definition(invalid))
      assert error.details.path == [:components, 0] ++ path
    end
  end

  test "internal-looking literal data is allowed in params and metadata" do
    data = %{kind: :call, call: %{kind: :action, target: :literal, params: %{}}}
    component = %{kind: :step, name: "echo", action: EchoParamsAction, params: data, meta: data}
    flow = Flow.new!(definition(component))

    assert flow.components["echo"].call.params == data
    assert flow.components["echo"].meta == data
    assert Jido.Exec.run(flow) == {:ok, data}
  end

  defp definition(component),
    do: %{name: "compact_data", components: [component], output: Ref.result(component.name)}

  defp components do
    [
      %{kind: :step, name: "step", action: EchoParamsAction},
      %{kind: :subflow, name: "child", flow: NestedFlow},
      %{
        kind: :choice,
        name: "choice",
        options: [%{name: "yes", condition: true, action: EchoParamsAction}],
        fallback: %{action: EchoParamsAction}
      },
      %{kind: :map, name: "map", collection: [], action: EchoParamsAction},
      %{kind: :reduce, name: "reduce", collection: [], initial: %{}, action: EchoParamsAction},
      %{
        kind: :iterate,
        name: "iterate",
        action: EchoParamsAction,
        state: %{initial: %{}, update: %{}},
        completion: true,
        max_iterations: 1
      },
      %{kind: :invoke, name: "invoke", decision: EchoParamsAction, expander: EchoParamsAction},
      %{kind: :handoff, name: "handoff", selector: EchoParamsAction}
    ]
  end
end
