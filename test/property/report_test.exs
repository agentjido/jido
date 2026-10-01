Code.require_file("support/report.exs", __DIR__)

defmodule JidoTest.Property.ReportTest do
  use ExUnit.Case, async: true
  @moduletag :property
  alias JidoTest.Property.Report

  setup do
    # ExUnit's default tmp_dir paths are shared by runtime jobs in one checkout.
    suffix = "#{System.pid()}-#{System.unique_integer([:positive])}"
    dir = Path.join([Mix.Project.build_path(), "property-report-tests", suffix])
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "contracts.md"),
      "| SIG-001 | Probe | Cases |\n| WIRE-001 | Wire | Cases |\n| WIRE-002 | Wire 2 | Cases |\n"
    )

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, tmp_dir: dir}
  end

  test "a new run replaces old evidence before test files load", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    File.write!(path, JSON.encode!(%{status: "finished", outcome: "passed"}))
    Report.prepare!(path)
    assert %{"status" => "incomplete", "started_at" => _} = report = read(path)
    refute Map.has_key?(report, "outcome")
  end

  test "incomplete disk report has the source metadata before the first test", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    {:ok, state} = Report.init(path: path, register: Path.join(dir, "contracts.md"))
    report = read(path)
    assert report == JSON.decode!(JSON.encode!(state.metadata))
    assert report["status"] == "incomplete"
    assert is_binary(report["revision"])
    assert is_boolean(report["working_tree_dirty"])
    assert Regex.match?(~r/\A[0-9a-f]{64}\z/, report["source_digest"])
    assert is_binary(report["runtime"])
    assert Map.has_key?(report["dependencies"], "jido_action")
  end

  test "register load failure leaves full incomplete metadata on disk", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")

    assert_raise File.Error, fn ->
      Report.init(path: path, register: Path.join(dir, "missing.md"))
    end

    report = read(path)
    assert report["status"] == "incomplete"
    assert is_binary(report["revision"])
    assert is_binary(report["source_digest"])
    assert is_binary(report["runtime"])
    assert is_map(report["dependencies"])
  end

  test "missing measurements cannot produce passed contract evidence", %{tmp_dir: dir} do
    record = test_record("missing artifact", nil, ["SIG-001"], ["SIG-001/boundary"])
    record = %{record | tags: Map.put(record.tags, :fuzz_id, "missing_group")}
    report = finish(dir, [record])
    assert report["outcome"] == "failed"
    assert report["contracts_with_passed_evidence"] == []
    assert [%{"id" => "missing_group", "suite" => "property"}] = report["artifact_errors"]
  end

  test "overlapping suite tags fail report validation", %{tmp_dir: dir} do
    record = test_record("overlap", nil, ["SIG-001"], [])
    record = %{record | tags: Map.put(record.tags, :fuzz, true)}
    report = finish(dir, [record])
    assert report["outcome"] == "failed"
    assert report["contracts_with_passed_evidence"] == []
  end

  test "a measurement must match its suite and contract declarations", %{tmp_dir: dir} do
    for wrong <- [%{variant: "fuzz"}, %{contracts: ["WIRE-001"]}, %{generated: 0}] do
      path = Path.join(dir, "report.json")
      {:ok, state} = Report.init(path: path, register: Path.join(dir, "contracts.md"))

      measurement =
        Map.merge(
          %{
            id: "matched_group",
            run_id: state.metadata.run_id,
            variant: "property",
            outcome: "passed",
            generated: 1,
            contracts: ["SIG-001"],
            declared_forced_cases: []
          },
          wrong
        )

      artifact =
        Path.join([dir, "property-fuzz", state.metadata.run_id, "matched_group-property.json"])

      Report.write!(artifact, measurement)
      test = test_record("mutated metadata", nil, ["SIG-001"], [])
      test = %{test | tags: Map.put(test.tags, :fuzz_id, "matched_group")}
      {:noreply, state} = Report.handle_cast({:test_finished, test}, state)
      {:noreply, _} = Report.handle_cast({:suite_finished, %{}}, state)
      assert read(path)["outcome"] == "failed"
      assert read(path)["contracts_with_passed_evidence"] == []
    end
  end

  test "source digest changes when an exported source file changes", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "guides"))
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "guides/public-contracts.md"), "| SIG-001 | Promise | Cases |\n")
    source = Path.join(dir, "lib/example.ex")
    File.write!(source, "first source")
    first = finish(dir, [], root: dir)
    File.write!(source, "second source")
    second = finish(dir, [], root: dir)
    refute first["source_digest"] == second["source_digest"]
  end

  test "failed and excluded declarations remain visible without passed case evidence", %{
    tmp_dir: dir
  } do
    report =
      finish(dir, [
        test_record("pass", nil, ["SIG-001"], ["SIG-001/missing"]),
        test_record("fail", {:failed, []}, ["SIG-001", "UNKNOWN-001"], ["UNKNOWN-001/case"]),
        test_record("exclude", {:excluded, []}, ["WIRE-001"], ["WIRE-001/raise"]),
        test_record("skip", {:skipped, []}, ["WIRE-002"], ["WIRE-002/after-callback"])
      ])

    assert report["outcome"] == "failed"
    assert report["contracts_with_passed_evidence"] == ["SIG-001"]
    assert report["declared_forced_cases_in_passed_tests"] == ["SIG-001/missing"]
    assert report["unknown_contract_ids"] == ["UNKNOWN-001"]
    assert report["invalid_case_ids"] == ["UNKNOWN-001/case"]
    assert "WIRE-001" in report["contracts_without_passed_evidence"]

    assert Enum.map(report["tests"], & &1["result"]) == [
             "excluded",
             "failed",
             "passed",
             "skipped"
           ]
  end

  test "a case must belong to a known contract declared by its test", %{tmp_dir: dir} do
    report =
      finish(dir, [test_record("invalid tags", nil, ["SIG-001"], ["WIRE-001/raise", "SIG-001/"])])

    assert Enum.sort(report["invalid_case_ids"]) == ["SIG-001/", "WIRE-001/raise"]
  end

  test "invalid passed declarations cannot supply global or suite evidence", %{tmp_dir: dir} do
    property = test_record("invalid property case", nil, ["SIG-001"], ["SIG-001:boundary"])
    fuzz = test_record("unknown fuzz contract", nil, ["WIRE-001", "UNKNOWN-001"], [])
    fuzz = %{fuzz | tags: fuzz.tags |> Map.delete(:property) |> Map.put(:fuzz, true)}
    valid = test_record("valid independent evidence", nil, ["WIRE-002"], ["WIRE-002/boundary"])
    report = finish(dir, [property, fuzz, valid])

    assert report["outcome"] == "failed"
    assert report["unknown_contract_ids"] == ["UNKNOWN-001"]
    assert report["invalid_case_ids"] == ["SIG-001:boundary"]
    assert report["contracts_with_passed_evidence"] == ["WIRE-002"]
    assert report["declared_forced_cases_in_passed_tests"] == ["WIRE-002/boundary"]
    evidence = report["contract_evidence_by_suite"]
    assert evidence["property"]["contracts_with_passed_evidence"] == ["WIRE-002"]
    assert evidence["fuzz"]["contracts_with_passed_evidence"] == []
    assert evidence["fuzz"]["declared_forced_cases_in_passed_tests"] == []
    assert Enum.all?(report["tests"], &(&1["result"] == "passed"))
  end

  test "an empty selection has no evidence and an invalid test fails the run", %{tmp_dir: dir} do
    assert finish(dir, [test_record("excluded", {:excluded, []}, ["SIG-001"], [])])["outcome"] ==
             "no_evidence"

    assert finish(dir, [test_record("invalid", {:invalid, nil}, ["SIG-001"], [])])["outcome"] ==
             "failed"

    # --include property can also run default tests. Their failures affect this outcome.
    normal = %{test_record("normal", {:failed, []}, [], []) | tags: %{}}
    assert finish(dir, [normal])["outcome"] == "failed"
  end

  test "an exported source tree has unknown Git metadata", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "guides"))
    File.write!(Path.join(dir, "guides/public-contracts.md"), "| SIG-001 | A promise | Cases |\n")

    report =
      finish(dir, [test_record("pass", nil, ["SIG-001"], [])],
        root: dir,
        register: Path.join(dir, "guides/public-contracts.md")
      )

    assert report["status"] == "finished"
    assert report["outcome"] == "passed"
    assert report["revision"] == nil
    assert report["working_tree_dirty"] == nil
    assert report["contracts_without_passed_evidence"] == []
  end

  test "fuzz evidence belongs only to the current run", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    {:ok, state} = Report.init(path: path, register: Path.join(dir, "contracts.md"))
    fuzz_dir = Path.join([dir, "property-fuzz", state.metadata.run_id])
    File.mkdir_p!(fuzz_dir)
    current = %{id: "current", run_id: state.metadata.run_id, generated: 7}
    stale = %{id: "stale", run_id: "previous-run", generated: 900}
    File.write!(Path.join(fuzz_dir, "current.json"), JSON.encode!(current))
    File.write!(Path.join(fuzz_dir, "stale.json"), JSON.encode!(stale))
    {:noreply, _} = Report.handle_cast({:suite_finished, %{}}, state)
    assert read(path)["fuzz"] == [JSON.decode!(JSON.encode!(current))]
  end

  test "old malformed files cannot break a new report", %{tmp_dir: dir} do
    fuzz_dir = Path.join([dir, "property-fuzz", "old-run"])
    File.mkdir_p!(fuzz_dir)
    File.write!(Path.join(fuzz_dir, "broken.json"), "not json")
    assert finish(dir, [test_record("pass", nil, ["SIG-001"], [])])["outcome"] == "passed"
  end

  test "a malformed current artifact produces a finished failed report", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    {:ok, state} = Report.init(path: path, register: Path.join(dir, "contracts.md"))
    fuzz_dir = Path.join([dir, "property-fuzz", state.metadata.run_id])
    File.mkdir_p!(fuzz_dir)
    File.write!(Path.join(fuzz_dir, "broken.json"), "not json")
    {:noreply, _} = Report.handle_cast({:suite_finished, %{}}, state)
    assert read(path)["status"] == "finished"
    assert read(path)["outcome"] == "failed"
    assert [%{"path" => _, "error" => _}] = read(path)["artifact_errors"]
  end

  test "fuzz-only tests contribute evidence", %{tmp_dir: dir} do
    record = test_record("fuzz pass", nil, ["SIG-001"], [])
    record = %{record | tags: record.tags |> Map.delete(:property) |> Map.put(:fuzz, true)}
    report = finish(dir, [record])
    assert report["outcome"] == "passed"
    assert report["contracts_with_passed_evidence"] == ["SIG-001"]
  end

  test "short properties cannot fill gaps in fuzz contract evidence", %{tmp_dir: dir} do
    property = test_record("short", nil, ["SIG-001"], ["SIG-001/short"])
    fuzz = test_record("long", nil, ["WIRE-001"], ["WIRE-001/long"])
    fuzz = %{fuzz | tags: fuzz.tags |> Map.delete(:property) |> Map.put(:fuzz, true)}
    failed = test_record("failed long", {:failed, []}, ["WIRE-002"], ["WIRE-002/long"])
    failed = %{failed | tags: failed.tags |> Map.delete(:property) |> Map.put(:fuzz, true)}
    report = finish(dir, [property, fuzz, failed])
    assert report["contracts_with_passed_evidence"] == ["SIG-001", "WIRE-001"]
    evidence = report["contract_evidence_by_suite"]
    assert evidence["property"]["contracts_with_passed_evidence"] == ["SIG-001"]
    assert evidence["fuzz"]["contracts_with_passed_evidence"] == ["WIRE-001"]
    assert evidence["fuzz"]["declared_forced_cases_in_passed_tests"] == ["WIRE-001/long"]
    assert "SIG-001" in evidence["fuzz"]["contracts_without_passed_evidence"]
    assert "WIRE-002" in evidence["fuzz"]["contracts_without_passed_evidence"]
  end

  defp test_record(name, state, contracts, cases) do
    %ExUnit.Test{
      module: __MODULE__,
      name: name,
      state: state,
      tags: %{property: true, contracts: contracts, contract_cases: cases}
    }
  end

  defp finish(dir, tests, options \\ []) do
    path = Path.join(dir, "report.json")

    {:ok, state} =
      Report.init(
        [path: path, register: Keyword.get(options, :register, Path.join(dir, "contracts.md"))] ++
          options
      )

    state =
      Enum.reduce(tests, state, fn test, state ->
        {:noreply, state} = Report.handle_cast({:test_finished, test}, state)
        state
      end)

    {:noreply, _} = Report.handle_cast({:suite_finished, %{}}, state)
    read(path)
  end

  defp read(path), do: path |> File.read!() |> JSON.decode!()
end
