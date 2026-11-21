Code.require_file("inputs_and_output.ex", __DIR__)

defmodule Jido.Examples.Compilation.InputsAndOutputTest do
  use ExUnit.Case, async: true
  @moduletag :integration

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
