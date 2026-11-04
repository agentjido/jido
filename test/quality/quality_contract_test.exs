Code.require_file("support/contract.exs", __DIR__)

defmodule Jido.Quality.ContractTest do
  use ExUnit.Case, async: true

  alias Jido.Quality.Contract

  @contract_path Path.join(__DIR__, "quality_contract.yml")
  @root Path.expand("../..", __DIR__)
  @today ~D[2026-11-04]

  test "the checked-in quality contract is valid" do
    assert Contract.validate(Contract.load!(@contract_path), @root, @today) == []
  end

  test "rejects a missing required suite and a duplicate suite id" do
    contract = contract()
    [unit | remaining] = contract["suites"]

    missing = put_in(contract, ["suites"], Enum.reject(remaining, &(&1["id"] == "authoring")))
    assert "required suite is missing: authoring" in Contract.validate(missing, @root, @today)

    duplicate = put_in(contract, ["suites"], [unit, unit | remaining])
    assert "duplicate suite id: unit" in Contract.validate(duplicate, @root, @today)
  end

  test "rejects an unknown suite state and alias" do
    invalid =
      contract()
      |> update_suite("unit", &Map.put(&1, "state", "sometimes"))
      |> update_suite("authoring", &Map.put(&1, "alias", "test.unknown"))

    errors = Contract.validate(invalid, @root, @today)
    assert "suite unit has unknown state: \"sometimes\"" in errors
    assert "suite authoring has unknown alias: \"test.unknown\"" in errors
  end

  test "rejects package and component thresholds below their floors" do
    invalid =
      contract()
      |> put_in(["thresholds", "line_coverage", "package_minimum_percent"], 89.9)
      |> put_in(["thresholds", "line_coverage", "component_minimum_percent"], 79.9)

    errors = Contract.validate(invalid, @root, @today)
    assert "package line coverage must be at least 90" in errors
    assert "component line coverage must be at least 80" in errors
  end

  test "rejects invalid Covenant, regression, and fuzz thresholds" do
    invalid =
      contract()
      |> put_in(["thresholds", "line_coverage", "maximum_component_regression_points"], 0.6)
      |> put_in(["thresholds", "covenant", "obligation_coverage_percent"], 99.9)
      |> put_in(["fuzz", "required_seed"], 1)
      |> put_in(["fuzz", "bounded_generators"], false)

    errors = Contract.validate(invalid, @root, @today)
    assert "maximum component regression must be between 0 and 0.5" in errors
    assert "Covenant obligation coverage must equal 100" in errors
    assert "fuzz required_seed must equal 0" in errors
    assert "fuzz generators must be bounded" in errors
  end

  test "rejects a waiver without ownership or an expiry condition" do
    waiver = %{
      "id" => "temporary-gap",
      "owner" => "",
      "reason" => "A temporary compatibility gap",
      "expires_on" => "2026-11-03",
      "resolution_condition" => ""
    }

    invalid = put_in(contract(), ["waivers"], [waiver])
    errors = Contract.validate(invalid, @root, @today)

    assert "waiver temporary-gap is missing owner" in errors
    assert "waiver temporary-gap is missing resolution_condition" in errors
    assert "waiver temporary-gap is expired" in errors
  end

  test "rejects evidence and report paths that leave the repository" do
    invalid =
      contract()
      |> update_suite("unit", &Map.put(&1, "evidence_artifacts", ["../outside.json"]))
      |> put_in(["reports", "json"], "/tmp/quality.json")

    errors = Contract.validate(invalid, @root, @today)
    assert "suite unit evidence artifact leaves the repository: \"../outside.json\"" in errors
    assert "report path leaves the repository: \"/tmp/quality.json\"" in errors
  end

  test "rejects incomplete and unowned stability findings" do
    finding = %{
      "id" => "race",
      "suite_id" => "unknown",
      "component" => "jido.persistence",
      "owner" => "",
      "status" => "pending",
      "observed_on" => "not-a-date",
      "reason" => "Observed failure",
      "resolution_condition" => "Find and fix the cause"
    }

    errors = Contract.validate(put_in(contract(), ["stability_findings"], [finding]), @root, @today)
    assert "stability finding race is missing owner" in errors
    assert "stability finding race has unknown status" in errors
    assert "stability finding race has unknown suite_id" in errors
    assert "stability finding race observed_on is invalid" in errors
  end

  defp contract, do: Contract.load!(@contract_path)

  defp update_suite(contract, id, update) do
    Map.update!(contract, "suites", fn suites ->
      Enum.map(suites, fn suite -> if suite["id"] == id, do: update.(suite), else: suite end)
    end)
  end
end
