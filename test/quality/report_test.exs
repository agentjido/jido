Code.require_file("support/contract.exs", __DIR__)
Code.require_file("support/component_proof.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)

defmodule Jido.Quality.ReportTest do
  use ExUnit.Case, async: true

  alias Jido.Quality.Report

  test "complete passing evidence produces matching JSON and text outcomes" do
    report = Report.evaluate(contract(), evidence(), metadata())

    assert report["outcome"] == "pass"
    assert report["findings"] == []
    assert Report.text(report) =~ "Outcome: PASS"
    assert Report.text(report) =~ "Covenant: 1/1"
  end

  test "a missing suite artifact fails and names the suite owner" do
    evidence =
      put_in(evidence(), ["suite_results", "unit", "artifacts"], [
        %{"path" => "tmp/quality/suites/unit.json", "exists" => false}
      ])

    report = Report.evaluate(contract(), evidence, metadata())
    finding = Enum.find(report["findings"], &String.starts_with?(&1["id"], "suite:unit:artifact"))

    assert report["outcome"] == "fail"
    assert finding["owner"] == "jido.package"
    assert finding["message"] =~ "unit"
  end

  test "Covenant, component proof, and coverage gaps name their components" do
    evidence =
      evidence()
      |> put_in(["covenant", "totals"], %{"active" => 1, "covered" => 0, "coverage" => 0.0})
      |> put_in(["covenant", "components", "jido.agent", "coverage"], 0.0)
      |> put_in(["component_proof_errors"], ["active component is missing: jido.agent"])
      |> put_in(["coverage", "status"], "fail")
      |> put_in(["coverage", "errors"], ["component jido.agent coverage 79.0% is below 80.0%"])

    report = Report.evaluate(contract(), evidence, metadata())
    messages = Enum.map(report["findings"], & &1["message"])

    assert Enum.any?(messages, &String.contains?(&1, "Covenant component jido.agent"))
    assert Enum.any?(messages, &String.contains?(&1, "component proof gap"))
    assert Enum.any?(messages, &String.contains?(&1, "component jido.agent coverage"))
  end

  test "an unresolved stability failure remains after a later suite pass" do
    finding = stability_finding()
    contract = put_in(contract(), ["stability_findings"], [finding])
    report = Report.evaluate(contract, evidence(), metadata())

    assert report["outcome"] == "fail"
    assert Enum.any?(report["findings"], &(&1["id"] == finding["id"] and &1["status"] == "open"))
  end

  test "a valid waiver changes only its owned finding and stays visible" do
    finding = stability_finding()

    waiver = %{
      "id" => "temporary-race-waiver",
      "finding_id" => finding["id"],
      "owner" => finding["owner"],
      "reason" => "The deterministic replacement check is in progress.",
      "expires_on" => "2026-12-04",
      "resolution_condition" => "Close when the cleanup order is deterministic."
    }

    contract = contract() |> put_in(["stability_findings"], [finding]) |> put_in(["waivers"], [waiver])
    report = Report.evaluate(contract, evidence(), metadata())

    assert report["outcome"] == "pass"
    assert report["waivers"] == [waiver]

    assert [%{"status" => "waived", "waiver_id" => "temporary-race-waiver"}] =
             Enum.map(report["findings"], &Map.take(&1, ["status", "waiver_id"]))
  end

  test "dirty state and runtime versions are present in both report forms" do
    report = Report.evaluate(contract(), evidence(), metadata())
    text = Report.text(report)

    assert report["metadata"]["dirty"] == true
    assert text =~ "Dirty: true"
    assert text =~ "Runtime: Elixir 1.20.4, OTP 29"
  end

  defp contract do
    %{
      "suites" => [
        %{
          "id" => "unit",
          "state" => "required",
          "owner" => "jido.package",
          "evidence_artifacts" => ["tmp/quality/suites/unit.json"]
        }
      ],
      "thresholds" => %{"covenant" => %{"obligation_coverage_percent" => 100}},
      "stability_findings" => [],
      "waivers" => []
    }
  end

  defp evidence do
    %{
      "suite_results" => %{
        "unit" => %{
          "outcome" => "pass",
          "owner" => "jido.package",
          "artifacts" => [%{"path" => "tmp/quality/suites/unit.json", "exists" => true}]
        }
      },
      "covenant" => %{
        "totals" => %{"active" => 1, "covered" => 1, "coverage" => 1.0},
        "components" => %{"jido.agent" => %{"coverage" => 1.0}}
      },
      "component_proof_errors" => [],
      "coverage" => %{
        "status" => "pass",
        "errors" => [],
        "metadata" => %{"revision" => "abc", "dirty" => true},
        "package" => %{"percent" => 93.0}
      }
    }
  end

  defp metadata do
    %{"revision" => "abc", "dirty" => true, "elixir" => "1.20.4", "otp" => "29"}
  end

  defp stability_finding do
    %{
      "id" => "covenant-cleanup-race",
      "suite_id" => "unit",
      "component" => "jido.agent",
      "owner" => "jido.agent",
      "status" => "unresolved",
      "reason" => "A cleanup race failed once."
    }
  end
end
