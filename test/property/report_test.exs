Code.require_file("support/report.exs", __DIR__)

defmodule Jido.Property.ReportTest do
  use ExUnit.Case, async: true

  @moduletag :property

  alias Jido.Test.Property.Report

  defmodule FamilyTest do
  end

  defmodule OtherFamilyTest do
  end

  @configs %{
    "family" => %{
      module_prefixes: ["Jido.Property.ReportTest.FamilyTest"],
      fuzz_ids: ["family_case"],
      required_observations: %{"family_case" => ["complete"]}
    },
    "other" => %{
      module_prefixes: ["Jido.Property.ReportTest.OtherFamilyTest"],
      fuzz_ids: ["other_case"],
      required_observations: %{}
    }
  }

  setup do
    suffix = "#{System.pid()}-#{System.unique_integer([:positive])}"
    dir = Path.join([Mix.Project.build_path(), "property-report-tests", suffix])
    File.mkdir_p!(dir)
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

  test "an incomplete report contains source metadata", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    {:ok, state} = Report.init(path: path, configs: @configs)
    report = read(path)
    assert report == JSON.decode!(JSON.encode!(state.metadata))
    assert is_binary(report["revision"])
    assert is_boolean(report["working_tree_dirty"])
    assert Regex.match?(~r/\A[0-9a-f]{64}\z/, report["source_digest"])
  end

  test "a focused run records only its selected family", %{tmp_dir: dir} do
    report = finish(dir, [test_record(FamilyTest, "property", nil)], configs: @configs)
    assert report["outcome"] == "passed"
    assert Map.keys(report["families"]) == ["family"]
    assert report["families"]["family"]["outcome"] == "passed"
  end

  test "property tests do not require fuzz measurements", %{tmp_dir: dir} do
    report = finish(dir, [test_record(FamilyTest, "property", nil)], configs: @configs)
    assert report["families"]["family"]["validation_errors"] == []
  end

  test "missing failed orphaned and duplicate measurements fail", %{tmp_dir: dir} do
    for fault <- [:missing, :failed, :orphaned, :duplicate] do
      path = Path.join(dir, "#{fault}.json")
      {:ok, state} = Report.init(path: path, configs: @configs)
      owner = test_record(FamilyTest, "fuzz", "family_case")

      state =
        if fault == :orphaned do
          state
        else
          {:noreply, state} = Report.handle_cast({:test_finished, owner}, state)
          state
        end

      if fault != :missing do
        record = measurement(state.metadata.run_id, outcome: if(fault == :failed, do: "failed", else: "passed"))
        write_measurement(dir, record)
        if fault == :duplicate, do: write_measurement(dir, record, "duplicate.json")
      end

      {:noreply, _state} = Report.handle_cast({:suite_finished, %{}}, state)
      assert read(path)["outcome"] == "failed"
    end
  end

  test "invalid and malformed measurements fail", %{tmp_dir: dir} do
    for {name, artifact} <- [
          {:invalid, measurement("run", generated: -1)},
          {:malformed, "not json"}
        ] do
      path = Path.join(dir, "#{name}.json")
      {:ok, state} = Report.init(path: path, configs: @configs)
      artifact = if is_map(artifact), do: %{artifact | run_id: state.metadata.run_id}, else: artifact
      write_measurement(dir, artifact, nil, state.metadata.run_id)
      {:noreply, _state} = Report.handle_cast({:suite_finished, %{}}, state)
      assert read(path)["outcome"] == "failed"
    end
  end

  test "only current-run measurements are used", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    {:ok, state} = Report.init(path: path, configs: @configs)
    owner = test_record(FamilyTest, "fuzz", "family_case")
    {:noreply, state} = Report.handle_cast({:test_finished, owner}, state)
    write_measurement(dir, measurement(state.metadata.run_id))
    write_measurement(dir, measurement("old-run"), "stale.json", state.metadata.run_id)
    {:noreply, _state} = Report.handle_cast({:suite_finished, %{}}, state)
    assert length(read(path)["families"]["family"]["measurements"]) == 1
  end

  test "required lifecycle observations must be present", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    {:ok, state} = Report.init(path: path, configs: @configs)
    owner = test_record(FamilyTest, "fuzz", "family_case")
    {:noreply, state} = Report.handle_cast({:test_finished, owner}, state)
    write_measurement(dir, measurement(state.metadata.run_id, observations: %{"partial" => 1}))
    {:noreply, _state} = Report.handle_cast({:suite_finished, %{}}, state)
    assert [error] = read(path)["families"]["family"]["validation_errors"]
    assert error =~ "missed observation complete"
  end

  test "a full run requires every family and every fuzz ID", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    report = finish(dir, [test_record(FamilyTest, "property", nil)], path: path, configs: @configs)
    assert report["outcome"] == "passed"

    assert_raise RuntimeError, ~r/missing property families/, fn ->
      Report.check!(path: path, full: true, suite: :property, configs: @configs)
    end
  end

  test "a focused infrastructure run may have no family evidence", %{tmp_dir: dir} do
    path = Path.join(dir, "report.json")
    report = finish(dir, [], path: path, configs: @configs)
    assert report["outcome"] == "no_evidence"
    assert :ok = Report.check!(path: path, full: false, suite: :property, configs: @configs)
  end

  test "the source digest changes with exported source", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "lib"))
    source = Path.join(dir, "lib/example.ex")
    File.write!(source, "first source")
    first = finish(dir, [], root: dir, configs: @configs)
    File.write!(source, "second source")
    second = finish(dir, [], root: dir, configs: @configs)
    refute first["source_digest"] == second["source_digest"]
  end

  defp test_record(module, suite, measurement_id) do
    tag = String.to_existing_atom(suite)

    %ExUnit.Test{
      module: module,
      name: "#{suite} proof",
      state: nil,
      tags: %{tag => true, fuzz_id: measurement_id}
    }
  end

  defp measurement(run_id, overrides \\ []) do
    Map.merge(
      %{
        id: "family_case",
        family: "family",
        run_id: run_id,
        variant: "fuzz",
        seed: 0,
        generated: 1,
        examples: 0,
        replayed: 0,
        shrink_attempts: 0,
        confirmations: 0,
        elapsed_ms: 1,
        outcome: "passed",
        observations: %{"complete" => 1},
        test_timeout: 90_000,
        limits: %{max_runs: 1, max_run_time: 10_000, max_shrinking_steps: 200}
      },
      Map.new(overrides)
    )
  end

  defp write_measurement(dir, record, name \\ nil, directory_run_id \\ nil) do
    run_id = directory_run_id || if(is_map(record), do: record.run_id, else: "unknown")
    path = Path.join([dir, "property-fuzz", run_id, "family", name || "family_case-fuzz.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, if(is_map(record), do: JSON.encode!(record), else: record))
  end

  defp finish(dir, tests, options) do
    path = Keyword.get(options, :path, Path.join(dir, "report.json"))
    {:ok, state} = Report.init(Keyword.put(options, :path, path))

    state =
      Enum.reduce(tests, state, fn test, state ->
        {:noreply, state} = Report.handle_cast({:test_finished, test}, state)
        state
      end)

    {:noreply, _state} = Report.handle_cast({:suite_finished, %{}}, state)
    read(path)
  end

  defp read(path), do: path |> File.read!() |> JSON.decode!()
end
