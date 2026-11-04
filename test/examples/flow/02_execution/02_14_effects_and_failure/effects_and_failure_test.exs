Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.EffectsAndFailureTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_14_effects_and_failure/effects_and_failure.ex")
    :ok
  end

  test "keeps successful effects in order and returns one later failure" do
    success = Jido.Examples.Execution.EffectsAndFailure.Success
    failure = Jido.Examples.Execution.EffectsAndFailure.Failure
    reject = Jido.Examples.Execution.EffectsAndFailure.Reject

    assert Jido.Exec.run(success, %{value: 3}) ==
             {:ok, %{value: 6}, [{:record_add, "first"}, {:record_add, "second"}]}

    assert {:error, %Jido.Error.ExecutionError{details: details}} = Jido.Exec.run(failure, %{value: 3})
    assert details.reason == :planned_rejection
    assert details.node == "reject"

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :planned_rejection}}} =
             Jido.Exec.run(reject)
  end
end
