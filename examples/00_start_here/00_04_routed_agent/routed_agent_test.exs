Code.require_file("routed_agent.ex", __DIR__)

defmodule Jido.Examples.StartHere.RoutedExpenseTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StartHere.RoutedExpense

  test "a Signal selects the Flow and returns a new Agent value" do
    source = RoutedExpense.instantiate!(id: "expense-router")
    {:ok, signal} = RoutedExpense.submit_signal(%{report_id: "report-7", amount_cents: 12_500})

    assert {:ok, candidate, []} = Jido.Agent.cmd(source, signal)
    assert candidate.state.status == :submitted
    assert candidate.state.review == :automatic
    assert source.state.status == :draft
  end

  test "invalid Signal data does not create a candidate" do
    source = RoutedExpense.instantiate!(id: "expense-router-invalid")
    {:ok, signal} = RoutedExpense.submit_signal(%{report_id: "", amount_cents: 0})

    assert {:error, %Jido.Error.ValidationError{}} = Jido.Agent.cmd(source, signal)
    assert source.state.status == :draft
  end
end
