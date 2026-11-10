Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.DynamicInvokeTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_15_dynamic_invoke/dynamic_invoke.ex")
    :ok
  end

  test "decision and expander select one runtime Action" do
    module = Jido.Examples.Execution.DynamicInvoke

    assert Jido.Exec.run(module, %{request: "calculate"}) ==
             {:ok, %{tool: "calculate", result: 42}}

    assert Jido.Exec.run(module, %{request: "Elixir"}) ==
             {:ok, %{tool: "search", result: "Elixir"}}

    flow = apply(module, :flow, [])
    assert flow.components["tool"].kind == :invoke

    assert Jido.Flow.dependencies(flow) ==
             {:ok, %{"tool" => %{needs: [], references: [], effective: []}}}
  end
end
