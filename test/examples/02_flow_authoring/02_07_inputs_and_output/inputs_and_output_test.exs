Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Compilation.InputsAndOutputTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("02_flow_authoring/02_07_inputs_and_output/inputs_and_output.ex")

    :ok
  end

  test "validates input and returns the exact explicit output" do
    module = Jido.Examples.Compilation.InputsAndOutput
    assert Jido.Exec.run(module, %{left: 2, right: 3}) == {:ok, %{answer: 5}}

    assert {:error, %Jido.Error.ValidationError{details: %{phase: :flow_input}}} =
             Jido.Exec.run(module, %{left: "two", right: 3})

    flow = apply(module, :flow, [])
    assert flow.output
    assert flow.schema
    assert flow.output_schema
  end
end
