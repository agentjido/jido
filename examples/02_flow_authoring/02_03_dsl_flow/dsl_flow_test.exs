Code.require_file("dsl_flow.ex", __DIR__)

defmodule Jido.Examples.Compilation.DSLFlowTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "DSL and direct data build the same canonical Flow" do
    alias Jido.Examples.Compilation.DSLFlow
    alias Jido.Examples.Compilation.DSLFlow.Echo
    alias Jido.Flow.Ref

    expected =
      Jido.Flow.new!(%{
        name: "example_compile_dsl",
        components: [
          %{kind: :step, name: "echo", action: Echo, params: %{message: Ref.input(:message)}}
        ],
        output: Ref.result("echo")
      })

    assert apply(DSLFlow, :flow, []) == expected
  end
end
