Code.require_file("submit_action.ex", __DIR__)

defmodule Jido.Examples.StartHere.SubmitExpenseTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StartHere.SubmitExpense

  test "one Action runs through the normal execution model" do
    assert {:ok, workflow} = Jido.Exec.compile(SubmitExpense, [])
    assert %Jido.Exec.Node.Action{name: "action"} = Runic.Workflow.get_component(workflow, "action")

    assert {:ok, %{report_id: "report-7", amount_cents: 12_500, status: :submitted}} =
             Jido.Exec.run(SubmitExpense, %{report_id: "report-7", amount_cents: 12_500})
  end

  test "invalid input does not run the Action" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(SubmitExpense, %{report_id: "", amount_cents: 0})
  end
end
