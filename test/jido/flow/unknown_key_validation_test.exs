defmodule Jido.Flow.UnknownKeyValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Test.Flow.Codec, as: Codec
  alias Jido.Flow.Definition
  alias Jido.Error.ValidationError
  alias Jido.Catalog
  alias Jido.Test.Action.Fixtures.Actions.Add

  test "Flow.new preserves valid input and rejects unknown root keys" do
    attrs = %{
      name: "flow",
      components: [%{kind: :step, name: "step", action: Add}],
      output: %{}
    }

    assert {:ok, flow} = Flow.new(attrs)
    assert Flow.validate(flow) == {:ok, flow}

    for unknown <- [
          %{unexpected: true},
          %{nil: :unexpected},
          %{nil: :unexpected, unexpected: true}
        ] do
      invalid = Map.merge(attrs, unknown)
      key = if Map.has_key?(unknown, nil), do: nil, else: :unexpected
      message = "unknown Flow configuration key: #{inspect(key)}"

      assert {:error,
              %ValidationError{
                message: ^message,
                details: %{key: ^key}
              }} = Flow.new(invalid)

      assert_raise ValidationError, message, fn -> Flow.new!(invalid) end
    end
  end

  test "component maps reject unknown keys at their own boundary" do
    cases = [
      {%{kind: :step, name: "step", action: Add}, "step"},
      {%{
         kind: :subflow,
         name: "child",
         flow: Jido.Test.Flow.Fixtures.NestedFlow
       }, "subflow"},
      {%{kind: :map, name: "map", collection: [], action: Add}, "map"},
      {%{kind: :parallel, name: "parallel", actions: [%{name: "add", action: Add}]}, "parallel"},
      {%{kind: :reduce, name: "reduce", collection: [], initial: %{}, action: Add}, "reduce"},
      {%{kind: :invoke, name: "invoke", decision: Add, expander: Add}, "invoke"},
      {%{
         kind: :iterate,
         name: "iterate",
         action: Add,
         state: %{initial: %{}, update: %{}},
         completion: true,
         max_iterations: 1
       }, "iterate"},
      {%{
         kind: :choice,
         name: "choice",
         options: [%{name: "yes", condition: true, action: Add}],
         fallback: %{action: Add}
       }, "choice"}
    ]

    for {attrs, _label} <- cases do
      assert {:ok, _named} = Definition.component(attrs)

      for unknown <- [
            %{unexpected: true},
            %{nil: :unexpected},
            %{nil: :unexpected, unexpected: true}
          ] do
        key = if Map.has_key?(unknown, nil), do: nil, else: :unexpected

        assert {:error, %ValidationError{} = error} =
                 attrs
                 |> Map.merge(unknown)
                 |> Definition.component()

        assert error.message == "unknown Flow field: #{inspect(key)}"
      end
    end
  end

  test "data authoring rejects unknown nested option, fallback, Action, and state keys" do
    option = %{name: "yes", condition: true, action: Add}
    fallback = %{action: Add}
    action = %{name: "add", action: Add}
    state = %{initial: %{}, update: %{}}

    for unknown <- [%{nil: :unexpected}, %{nil: :unexpected, unexpected: true}] do
      for {component, message, local_path} <- [
            {%{
               kind: :choice,
               name: "choice",
               options: [Map.merge(option, unknown)],
               fallback: fallback
             }, "unknown Flow field: nil", [:options, 0]},
            {%{
               kind: :choice,
               name: "choice",
               options: [option],
               fallback: Map.merge(fallback, unknown)
             }, "unknown Flow field: nil", [:fallback]},
            {%{
               kind: :parallel,
               name: "parallel",
               actions: [Map.merge(action, unknown)]
             }, "unknown Flow field: nil", [:actions, 0]},
            {%{
               kind: :iterate,
               name: "iterate",
               action: Add,
               state: Map.merge(state, unknown),
               completion: true,
               max_iterations: 1
             }, "unknown Flow field: nil", [:state]}
          ] do
        assert {:error, %ValidationError{} = error} =
                 Flow.new(%{name: "nested", components: [component], output: %{}})

        assert error.message == message
        assert error.details.path == [:components, 0] ++ local_path ++ [nil]
      end
    end
  end

  test "Codec rejects unknown root and component fields" do
    flow =
      Flow.new!(%{
        name: "stored",
        components: [%{kind: :step, name: "step", action: Add}],
        output: %{}
      })

    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"add", 1} => {:action, Add},
        {"map", 1} => {:schema, Jido.Joi.map()}
      })

    assert {:ok, document} = Codec.encode(flow, registry)
    refute Map.has_key?(document, "schema")
    refute Map.has_key?(document, "output_schema")
    assert {:ok, ^flow} = Codec.decode(document, registry)

    for unknown <- [%{nil: :unexpected}, %{nil: :unexpected, unexpected: true}] do
      for {invalid, path} <- [
            {Map.merge(document, unknown), ["nil"]},
            {update_in(document, ["components", Access.at(0)], &Map.merge(&1, unknown)), ["components", 0, "nil"]}
          ] do
        assert {:error,
                %ValidationError{
                  message: _message,
                  details: %{key: nil, path: ^path}
                }} = Codec.decode(invalid, registry)
      end
    end
  end
end

defmodule Jido.Flow.UnknownKeyDSLValidationTest do
  use ExUnit.Case, async: false

  for {suffix, unknown} <- [
        {"Nil", %{nil: :unexpected}},
        {"NilAndUnknown", %{nil: :unexpected, unexpected: true}}
      ] do
    test "DSL rejects unknown Flow configuration #{inspect(unknown)}" do
      module = Module.concat(__MODULE__, unquote(suffix))
      attrs = Map.merge(%{name: "invalid_config"}, unquote(Macro.escape(unknown)))

      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
      end)

      source = "defmodule #{inspect(module)} do
  use Jido.Flow, #{inspect(attrs)}
  flow do
    step \"step\", action: Jido.Test.Action.Fixtures.Actions.Add, params: %{}
    output %{}
  end
end
"

      error =
        assert_raise CompileError, fn -> Code.compile_string(source, "unknown_flow_key.ex") end

      assert error.file == "unknown_flow_key.ex"
      assert error.line == 2
      assert error.description =~ "unknown Flow configuration key: nil"
    end
  end
end
