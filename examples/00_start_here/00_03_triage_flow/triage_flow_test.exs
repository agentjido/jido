Code.require_file("triage_flow.ex", __DIR__)

defmodule Jido.Examples.StartHere.TriageExpenseTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StartHere.TriageExpense

  test "the Flow composes submission and review classification" do
    assert {:ok, %{status: :submitted, review: :automatic}} =
             Jido.Exec.run(TriageExpense, %{report_id: "report-7", amount_cents: 12_500})

    assert {:ok, %{status: :submitted, review: :manual}} =
             Jido.Exec.run(TriageExpense, %{report_id: "report-8", amount_cents: 75_000})
  end

  test "Flow input validation stops all work" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(TriageExpense, %{report_id: "", amount_cents: 75_000})
  end
end
