Code.require_file("evaluate_run.ex", __DIR__)

defmodule Jido.Examples.Evaluation.RunChecksTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Evaluation.RunChecks

  test "checks tool arguments, guardrails, token, cost, and latency budgets" do
    [passing, failing] =
      __DIR__ |> Path.join("fixtures/runs.json") |> File.read!() |> JSON.decode!()

    assert {:ok, pass_result} = Jido.Exec.run(RunChecks, atomize_top_level(passing))
    assert pass_result.passed
    assert Enum.all?(pass_result.checks, fn {_name, passed?} -> passed? end)

    assert {:ok, fail_result} = Jido.Exec.run(RunChecks, atomize_top_level(failing))
    refute fail_result.passed
    refute fail_result.checks.total_tokens
    refute fail_result.checks.total_cost
    refute fail_result.checks.latency_ms
    assert fail_result.checks.tool_trajectory
    assert fail_result.checks.guardrail
  end

  defp atomize_top_level(%{"run" => run, "expected" => expected}),
    do: %{run: run, expected: expected}
end
