Code.require_file("support/result.exs", __DIR__)

defmodule JidoTest.Bench.ResultTest do
  use ExUnit.Case, async: true

  @moduletag :bench

  alias Jido.Bench.Result

  test "a complete common result is valid" do
    report = report()
    assert Result.validate(report) == []
    assert Result.case_inventory(report) == ["case/one", "case/two"]
  end

  test "incompatible and incomplete results are rejected" do
    invalid =
      report()
      |> Map.put(:benchmark_result_schema_version, 2)
      |> put_in([:metadata, :git_revision], "")
      |> put_in([:metadata, :checkout_dirty], "false")
      |> put_in([:metadata, :seed], 99)
      |> Map.put(:cases, [%{id: "duplicate"}, %{id: "duplicate"}, %{}])

    errors = Result.validate(invalid)
    assert "benchmark result schema is incompatible" in errors
    assert "benchmark metadata is missing git_revision" in errors
    assert "benchmark metadata checkout_dirty must be boolean" in errors
    assert "benchmark metadata seed must equal 0" in errors
    assert "every benchmark case must have an id" in errors
    assert "benchmark case ids must be unique" in errors
  end

  test "decoded JSON uses the same result contract" do
    decoded = report() |> JSON.encode!() |> JSON.decode!()
    assert Result.validate(decoded) == []
    assert Result.case_inventory(decoded) == ["case/one", "case/two"]
  end

  defp report do
    %{
      benchmark_result_schema_version: Result.schema_version(),
      metadata: Result.metadata("jido.action_flow.compile", "quick"),
      cases: [%{id: "case/one"}, %{id: "case/two"}]
    }
  end
end
