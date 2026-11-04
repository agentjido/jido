Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.DynamicInvokeTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_15_dynamic_invoke/dynamic_invoke.ex")
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
