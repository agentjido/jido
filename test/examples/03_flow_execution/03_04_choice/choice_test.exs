Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.ChoiceTest do
  use ExUnit.Case, async: true
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("03_flow_execution/03_04_choice/choice.ex")
    :ok
  end

  test "selects the first matching option or fallback" do
    module = Jido.Examples.Execution.Choice
    assert Jido.Exec.run(module, %{score: 95}) == {:ok, %{label: "excellent"}}
    assert Jido.Exec.run(module, %{score: 75}) == {:ok, %{label: "passing"}}
    assert Jido.Exec.run(module, %{score: 40}) == {:ok, %{label: "needs_work"}}

    assert {:error, %Jido.Error.ValidationError{details: %{phase: :flow_input}}} =
             Jido.Exec.run(module, %{score: "high"})
  end
end
