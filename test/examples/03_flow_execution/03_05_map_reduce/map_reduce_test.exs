Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.MapReduceTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("03_flow_execution/03_05_map_reduce/map_reduce.ex")
    :ok
  end

  test "maps and reduces an ordered list and its empty case" do
    module = Jido.Examples.Execution.MapReduce

    assert Jido.Exec.run(module, %{values: [3, 1, 2]}) ==
             {:ok,
              %{
                items: [%{value: 6, index: 0}, %{value: 2, index: 1}, %{value: 4, index: 2}],
                total: %{total: 12}
              }}

    assert Jido.Exec.run(module, %{values: []}) == {:ok, %{items: [], total: %{total: 0}}}
  end
end
