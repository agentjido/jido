Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.ReduceTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_09_reduce/reduce.ex")
    :ok
  end

  test "updates one accumulator in order" do
    module = Jido.Examples.Execution.Reduce

    assert Jido.Exec.run(module, %{values: [3, 1, 2]}, %{observer: self()}) ==
             {:ok, %{total: 6}, [{:reduced, 0}, {:reduced, 1}, {:reduced, 2}]}

    assert_receive {:reduce_item, 0, 0, 3}
    assert_receive {:reduce_item, 1, 3, 1}
    assert_receive {:reduce_item, 2, 4, 2}
    assert Jido.Exec.run(module, %{values: []}) == {:ok, %{total: 0}}
  end
end
