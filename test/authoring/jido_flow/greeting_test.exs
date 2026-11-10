Code.require_file("../support/jido_flow/greeting.ex", __DIR__)

defmodule Jido.Flow.Authoring.GreetingTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Flow.{Codec, Ref}
  alias Jido.Test.Flow.Codec, as: Codec
  alias Jido.Test.Flow.Authoring.Greeting.{Flow, Greet, Normalize}

  test "an authored Action validates input and carries caller context" do
    assert {:ok, %{name: "Ada"}} = Jido.Exec.run(Normalize, %{name: " Ada "})
    assert {:ok, %{message: "Hi, Ada!"}} = Jido.Exec.run(Greet, %{name: "Ada"}, %{prefix: "Hi"})

    assert {:error,
            %Jido.Error.ValidationError{
              message: "invalid type: expected string, at name",
              details: %{
                module: Normalize,
                context: "Action",
                errors: [%{code: :invalid_type, path: [:name]}]
              }
            }} =
             Jido.Exec.run(Normalize, %{name: 12})
  end

  test "module DSL, and constructors author the same executable Flow" do
    module_flow = Flow.flow()

    data = %{
      output: Jido.Flow.Ref.result("greet"),
      components: [
        %{
          kind: :step,
          name: "normalize",
          action: Normalize,
          params: %{name: Jido.Flow.Ref.input(:name)}
        },
        %{
          kind: :step,
          name: "greet",
          action: Greet,
          params: %{name: Jido.Flow.Ref.result("normalize", :name)}
        }
      ],
      name: Flow.name(),
      schema: Flow.schema(),
      output_schema: Flow.output_schema()
    }

    assert {:ok, data_flow} = Jido.Test.Flow.Builder.new(data)

    direct_flow =
      Jido.Test.Flow.Builder.new!(
        name: Flow.name(),
        schema: Flow.schema(),
        output_schema: Flow.output_schema(),
        components: [
          Jido.Test.Flow.Component.step!(
            name: "normalize",
            action: Normalize,
            params: %{name: Ref.input(:name)}
          ),
          Jido.Test.Flow.Component.step!(
            name: "greet",
            action: Greet,
            params: %{name: Ref.result("normalize", :name)}
          )
        ],
        output: Ref.result("greet")
      )

    assert module_flow == data_flow
    assert module_flow == direct_flow

    for authored <- [Flow, module_flow, data_flow, direct_flow] do
      assert {:ok, %{message: "Hi, Ada!"}} =
               Jido.Exec.run(authored, %{name: " Ada "}, %{prefix: "Hi"})
    end
  end

  test "stored JSON restores the authored Flow through a trusted registry" do
    flow = Flow.flow()
    assert {:ok, document, registry} = Codec.encode(flow)
    assert {:ok, restored} = Codec.decode(document |> JSON.encode!() |> JSON.decode!(), registry)
    assert restored == flow

    assert {:ok, %{message: "Hello, Ada!"}} =
             Jido.Exec.run(restored, %{name: " Ada "}, %{prefix: "Hello"})
  end

  test "a source Flow without an output fails at authoring time" do
    assert_raise CompileError, ~r/Flow output is required/, fn ->
      Code.compile_file(Path.join(__DIR__, "../support/jido_flow/missing_output.ex"))
    end
  end
end
