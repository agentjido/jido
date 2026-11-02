defmodule Jido.AI.Contract.BudgetPolicyTest do
  use Covenant.Case, component: "jido_ai.model_execution", async: true

  alias Jido.AI.{Budget, Usage}

  @tag obligation: ["jido_ai.model_execution.I2", "jido_ai.model_execution.I3"]
  test "budgets check elapsed time, tokens, and provider-reported cost" do
    turn = %{
      started_at_ms: 1_000,
      model_calls: 0,
      max_model_calls: 3,
      max_elapsed_ms: 500,
      max_input_tokens: 100,
      max_output_tokens: 100,
      max_total_tokens: 150,
      max_total_cost: 0.25,
      usage: Usage.add(Usage.zero(), %{input_tokens: 80, output_tokens: 20, total_cost: 0.2})
    }

    assert :ok = Budget.before_model(turn, 1_400)

    assert {:error, :elapsed_ms, "maximum elapsed time reached"} =
             Budget.before_model(turn, 1_500)

    costly = put_in(turn, [:usage, :total_cost], 0.25)

    assert {:error, :total_cost, "maximum total cost reached"} =
             Budget.resources(costly, 1_400)

    assert turn.usage.total_cost == 0.2
  end
end
