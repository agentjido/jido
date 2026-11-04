Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.IterateTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_10_iterate/iterate.ex")
    :ok
  end

  test "returns final state and enforces its bound" do
    module = Jido.Examples.Execution.Iterate

    assert {:ok, result, [{:iteration, 0}, {:iteration, 1}, {:iteration, 2}]} =
             Jido.Exec.run(module, %{start: 0, target: 3})

    assert result.iterations == 3
    assert result.state == %{count: 3}

    assert {:error, %Jido.Error.ExecutionError{details: details}} =
             Jido.Exec.run(module, %{start: 0, target: 10})

    assert details.node == "counter"
    assert details.completed_iterations == 4
  end
end
