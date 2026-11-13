defmodule Jido.Examples.Evaluation.DeterministicCase.Score do
  use Jido.Action, name: "example_evaluation_score_case"

  @impl true
  def run(%{case: evaluation_case}, _context) do
    expected = evaluation_case["expected"]
    actual = evaluation_case["actual"]

    checks = %{
      exact_output: actual["output"] == expected["output"],
      status: actual["status"] == expected["status"],
      required_citation: citation_check(actual["output"], expected["required_citation"]),
      refusal: actual["refusal"] == expected["refusal"]
    }

    {:ok,
     %{
       case_id: evaluation_case["id"],
       checks: checks,
       score: Enum.count(checks, fn {_name, passed?} -> passed? end) / map_size(checks),
       passed: Enum.all?(checks, fn {_name, passed?} -> passed? end)
     }}
  end

  defp citation_check(_output, nil), do: true
  defp citation_check(output, citation), do: String.contains?(output, citation)
end

defmodule Jido.Examples.Evaluation.DeterministicCase do
  use Jido.Flow,
    name: "example_evaluation_deterministic_case",
    schema: Jido.Joi.object(%{case: Jido.Joi.map()})

  flow do
    step "score",
      action: Jido.Examples.Evaluation.DeterministicCase.Score,
      params: %{case: input(:case)}

    output result("score")
  end
end
