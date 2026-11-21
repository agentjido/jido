Code.require_file("evaluate_case.ex", __DIR__)

defmodule Jido.Examples.Evaluation.DeterministicCaseTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Evaluation.DeterministicCase

  test "all named fixture cases pass deterministic scorers" do
    cases = __DIR__ |> Path.join("fixtures/cases.json") |> File.read!() |> JSON.decode!()

    results =
      Enum.map(cases, fn evaluation_case ->
        assert {:ok, result} = Jido.Exec.run(DeterministicCase, %{case: evaluation_case})
        result
      end)

    assert Enum.map(results, & &1.case_id) == ["cited-answer", "policy-refusal"]
    assert Enum.all?(results, & &1.passed)
    assert Enum.all?(results, &(&1.score == 1.0))
  end

  test "a changed output fails exact and citation checks" do
    evaluation_case = %{
      "id" => "regression",
      "expected" => %{
        "output" => "The limit is 30 days [doc-1].",
        "status" => "completed",
        "required_citation" => "[doc-1]",
        "refusal" => false
      },
      "actual" => %{
        "output" => "The limit is 60 days.",
        "status" => "completed",
        "refusal" => false
      }
    }

    assert {:ok, result} = Jido.Exec.run(DeterministicCase, %{case: evaluation_case})
    refute result.passed
    refute result.checks.exact_output
    refute result.checks.required_citation
  end
end
