Code.require_file("validated_state.ex", __DIR__)

defmodule Jido.Examples.StartHere.ValidatedExpenseTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StartHere.ValidatedExpense

  test "state defaults and explicit values pass the declared schema" do
    draft = ValidatedExpense.instantiate!(id: "expense-draft")

    assert draft.state == %{report_id: "", amount_cents: 0, status: :draft}
    assert {:ok, ^draft} = Jido.Agent.validate(draft)

    submitted =
      ValidatedExpense.instantiate!(
        id: "expense-submitted",
        state: %{report_id: "report-7", amount_cents: 12_500, status: :submitted}
      )

    assert submitted.state.amount_cents == 12_500
  end

  test "invalid state is rejected before an Agent instance exists" do
    assert {:error, %Jido.Error.ValidationError{path: [:state]}} =
             ValidatedExpense.instantiate(
               id: "expense-invalid",
               state: %{report_id: "report-8", amount_cents: -1, status: :submitted}
             )
  end
end
