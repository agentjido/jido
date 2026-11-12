Code.require_file("effects_and_failure.ex", __DIR__)

defmodule Jido.Examples.Execution.EffectsAndFailureTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "Exec returns ordered effects and one normalized failure" do
    success = Jido.Examples.Execution.EffectsAndFailure.Success
    failure = Jido.Examples.Execution.EffectsAndFailure.Failure

    assert Jido.Exec.run(success, %{value: 3}) ==
             {:ok, %{value: 6}, [{:record_add, "first"}, {:record_add, "second"}]}

    assert {:error, %Jido.Error.ExecutionError{details: details}} =
             Jido.Exec.run(failure, %{value: 3})

    assert details.reason == :planned_rejection
    assert details.node == "reject"
  end
end
