Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.SingleActionTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_01_single_action/single_action.ex")
    :ok
  end

  test "runs modules, Instructions, and explicit outputs" do
    add = Jido.Examples.Execution.SingleAction.Add

    assert Jido.Exec.run(add, %{value: 3, amount: 2}, %{source: "direct"}) ==
             {:ok, %{source: "direct", value: 5}}

    instruction =
      Jido.Instruction.new!(
        target: add,
        params: %{value: 3, amount: 5},
        context: %{source: "instruction"}
      )

    assert Jido.Exec.run(instruction) == {:ok, %{source: "instruction", value: 8}}

    assert {:ok, %Jido.Action.Output{kind: :raw, value: "ready", meta: %{source: "example"}}} =
             Jido.Exec.run(Jido.Examples.Execution.SingleAction.ExplicitOutput, %{value: "ready"})
  end

  test "rejects invalid input and nested directives" do
    assert {:error, %Jido.Error.ValidationError{details: %{errors: [error]}}} =
             Jido.Exec.run(
               Jido.Examples.Execution.SingleAction.Add,
               %{value: "three", amount: 2},
               %{source: "direct"}
             )

    assert error.code == :invalid_type
    assert error.path == [:value]

    directive = {:continue, %{value: 1}, Jido.Examples.Execution.SingleAction.Add}

    for target <- [
          Jido.Examples.Execution.SingleAction.Return,
          Jido.Examples.Execution.SingleAction.DirectiveFlow
        ] do
      assert {:error, %Jido.Error.ExecutionError{details: %{reason: :unsupported_continuation}}} =
               Jido.Exec.run(target, %{reply: directive})
    end
  end
end
