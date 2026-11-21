defmodule Jido.Examples.Evaluation.RunChecks.Check do
  use Jido.Action, name: "example_evaluation_check_run"

  @impl true
  def run(%{run: run, expected: expected}, _context) do
    checks = %{
      tool_trajectory: run["tool_trajectory"] == expected["tool_trajectory"],
      total_tokens: run["usage"]["total_tokens"] <= expected["budgets"]["total_tokens"],
      total_cost: run["usage"]["total_cost"] <= expected["budgets"]["total_cost"],
      latency_ms: run["latency_ms"] <= expected["budgets"]["latency_ms"],
      guardrail: run["guardrail"] == expected["guardrail"]
    }

    {:ok,
     %{
       run_id: run["id"],
       checks: checks,
       passed: Enum.all?(checks, fn {_name, passed?} -> passed? end),
       observed: %{
         total_tokens: run["usage"]["total_tokens"],
         total_cost: run["usage"]["total_cost"],
         latency_ms: run["latency_ms"]
       }
     }}
  end
end

defmodule Jido.Examples.Evaluation.RunChecks do
  use Jido.Flow,
    name: "example_evaluation_run_checks",
    schema: Jido.Joi.object(%{run: Jido.Joi.map(), expected: Jido.Joi.map()})

  flow do
    step "check",
      action: Jido.Examples.Evaluation.RunChecks.Check,
      params: %{run: input(:run), expected: input(:expected)}

    output result("check")
  end
end
