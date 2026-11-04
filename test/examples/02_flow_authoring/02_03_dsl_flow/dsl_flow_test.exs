Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Compilation.DSLFlowTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("02_flow_authoring/02_03_dsl_flow/dsl_flow.ex")
    :ok
  end

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
