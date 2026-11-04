Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.ThreeStepFlowTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("03_flow_execution/03_02_three_step_flow/three_step_flow.ex")
    :ok
  end

  test "runs three dependent Actions and validates Flow input" do
    module = Jido.Examples.Execution.ThreeStepFlow
    assert Jido.Exec.run(module, %{value: 3}) == {:ok, %{value: 8, label: "value=8"}}

    assert {:error, %Jido.Error.ValidationError{details: %{phase: :flow_input}}} =
             Jido.Exec.run(module, %{value: "three"})
  end
end
