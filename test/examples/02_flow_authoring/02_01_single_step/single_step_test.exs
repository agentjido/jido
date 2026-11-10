Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Compilation.SingleStepTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("02_flow_authoring/02_01_single_step/single_step.ex")
    :ok
  end

  test "builds one canonical component with no dependencies" do
    module = Jido.Examples.Compilation.SingleStep
    flow = apply(module, :flow, [])
    assert Map.keys(flow.components) == ["echo"]

    assert Jido.Flow.dependencies(flow) ==
             {:ok, %{"echo" => %{needs: [], references: [], effective: []}}}
  end

  test "requires an explicit output" do
    definition = Map.delete(apply(Jido.Examples.Compilation.SingleStep, :definition, []), :output)
    assert {:error, error} = Jido.Flow.new(definition)
    assert error.message == "Flow output is required"
    assert error.details.path == [:output]
  end
end
