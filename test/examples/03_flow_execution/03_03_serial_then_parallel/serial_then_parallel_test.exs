Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.SerialThenParallelTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_03_serial_then_parallel/serial_then_parallel.ex")
    :ok
  end

  test "runs serial work, a keyed parallel join, and final work" do
    module = Jido.Examples.Execution.SerialThenParallel

    assert Jido.Exec.run(module, %{value: 4}) ==
             {:ok,
              %{
                final: %{value: 23},
                parallel: %{
                  "plus_ten" => %{value: 20},
                  "times_three" => %{value: 30},
                  "minus_two" => %{value: 8}
                }
              }}

    {:ok, dependencies} = Jido.Flow.dependencies(apply(module, :flow, []))
    assert dependencies["branches"].references == ["second"]
    assert dependencies["third"].references == ["branches"]
  end
end
