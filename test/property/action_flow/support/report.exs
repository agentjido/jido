defmodule JidoTest.Property.ActionFlow.Report do
  @moduledoc false
  use GenServer

  @root Path.expand("../../../..", __DIR__)
  @required_contract_ids ~w(EXPR-001 EXPR-002)
  @fuzz_ids ~w(expression_trees)

  def fuzz_ids, do: Enum.sort(@fuzz_ids)

  def check!(path \\ report_path(), required_fuzz_ids \\ @fuzz_ids) do
    report = path |> File.read!() |> JSON.decode!()

    unless report["status"] == "finished" and report["outcome"] == "passed",
      do: raise("Action and Flow property report did not pass: #{inspect(report["outcome"])}")

    completed = for record <- report["fuzz"], record["variant"] == "fuzz", do: record["id"]
    missing = required_fuzz_ids -- completed
    if missing != [], do: raise("missing fuzz cases: #{Enum.join(missing, ", ")}")
    :ok
  end

  # Call before test files compile. A load failure must not retain old evidence.
  def prepare!(path \\ report_path()) do
    report = %{
      status: "incomplete",
      started_at: DateTime.to_iso8601(DateTime.utc_now()),
      run_id: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    }

    write!(path, report)
    report
  end

  @impl true
  def init(options) do
    path = Keyword.get(options, :path, report_path())
    root = Keyword.get(options, :root, @root)
    ids = Keyword.get_lazy(options, :contract_ids, fn -> contract_ids(root) end)

    metadata =
      prepare!(path)
      |> Map.merge(git_metadata(root))
      |> Map.merge(%{
        package_version: Mix.Project.config()[:version],
        elixir: System.version(),
        otp: System.otp_release(),
        exunit_seed: ExUnit.configuration()[:seed],
        selection: %{
          include: inspect(ExUnit.configuration()[:include]),
          exclude: inspect(ExUnit.configuration()[:exclude])
        }
      })

    {:ok, %{path: path, metadata: metadata, ids: ids, records: [], failed?: false}}
  end

  @impl true
  def handle_cast({:test_finished, test}, state) do
    if action_flow_test?(test) do
      result = result(test.state)
      state = %{state | failed?: state.failed? or result in ["failed", "invalid"]}

      if test.tags[:property] || test.tags[:fuzz] do
        record = %{
          test: "#{inspect(test.module)}: #{test.name}",
          suite: if(test.tags[:fuzz], do: "fuzz", else: "property"),
          measurement_id: test.tags[:fuzz_id],
          contracts: Map.get(test.tags, :contracts, []),
          declared_forced_cases: Map.get(test.tags, :contract_cases, []),
          result: result
        }

        {:noreply, %{state | records: [record | state.records]}}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:suite_finished, _times}, state) do
    {fuzz, artifact_errors} = fuzz_records(state)
    passed = Enum.filter(state.records, &(&1.result == "passed"))
    evidenced = passed |> Enum.flat_map(& &1.contracts) |> Enum.uniq() |> Enum.sort()
    cases = passed |> Enum.flat_map(& &1.declared_forced_cases) |> Enum.uniq() |> Enum.sort()
    declared = state.records |> Enum.flat_map(& &1.contracts) |> Enum.uniq()
    unknown = Enum.sort(declared -- state.ids)
    invalid = invalid_case_ids(state.records, state.ids)
    validation_errors = measurement_errors(state.records, fuzz)

    report =
      Map.merge(state.metadata, %{
        status: "finished",
        finished_at: DateTime.to_iso8601(DateTime.utc_now()),
        outcome:
          cond do
            state.failed? or artifact_errors != [] or validation_errors != [] or
              unknown != [] or invalid != [] ->
              "failed"

            evidenced == [] ->
              "no_evidence"

            true ->
              "passed"
          end,
        contracts_with_passed_evidence: evidenced,
        declared_forced_cases_in_passed_tests: cases,
        contracts_without_passed_evidence: Enum.sort(state.ids -- evidenced),
        contract_evidence_by_suite:
          Map.new(["property", "fuzz"], fn suite ->
            {suite, evidence(Enum.filter(state.records, &(&1.suite == suite)), state.ids)}
          end),
        unknown_contract_ids: unknown,
        invalid_case_ids: invalid,
        validation_errors: validation_errors,
        tests: Enum.sort_by(state.records, & &1.test),
        fuzz: fuzz,
        artifact_errors: artifact_errors
      })

    write!(state.path, report)
    {:noreply, state}
  end

  def handle_cast(_event, records), do: {:noreply, records}

  defp evidence(records, ids) do
    passed = Enum.filter(records, &(&1.result == "passed"))
    contracts = passed |> Enum.flat_map(& &1.contracts) |> Enum.uniq() |> Enum.sort()

    %{
      contracts_with_passed_evidence: contracts,
      contracts_without_passed_evidence: Enum.sort(ids -- contracts),
      declared_forced_cases_in_passed_tests:
        passed |> Enum.flat_map(& &1.declared_forced_cases) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp fuzz_records(state) do
    Path.join([Path.dirname(state.path), "action-flow-property-fuzz", state.metadata.run_id, "*.json"])
    |> Path.wildcard()
    |> Enum.reduce({[], []}, fn path, {records, errors} ->
      with {:ok, data} <- File.read(path),
           {:ok, record} when is_map(record) <- JSON.decode(data) do
        cond do
          record["run_id"] != state.metadata.run_id -> {records, errors}
          valid_measurement?(record, state.ids) -> {[record | records], errors}
          true -> {records, [%{path: path, error: "invalid fuzz measurement"} | errors]}
        end
      else
        error -> {records, [%{path: path, error: inspect(error)} | errors]}
      end
    end)
    |> then(fn {records, errors} ->
      {Enum.sort_by(records, &{&1["id"], &1["variant"]}), Enum.sort_by(errors, & &1.path)}
    end)
  end

  defp valid_measurement?(record, ids) do
    limits = record["limits"]
    counts = ~w(generated examples replayed shrink_attempts confirmations elapsed_ms)

    record["id"] in @fuzz_ids and record["variant"] in ["fuzz", "property"] and
      record["outcome"] in ["passed", "failed", "incomplete"] and
      is_integer(record["seed"]) and is_integer(record["test_timeout"]) and
      record["test_timeout"] > 0 and
      Enum.all?(counts, &(is_integer(record[&1]) and record[&1] >= 0)) and
      is_map(limits) and is_integer(limits["max_runs"]) and limits["max_runs"] > 0 and
      is_integer(limits["max_run_time"]) and limits["max_run_time"] > 0 and
      is_integer(limits["max_shrinking_steps"]) and limits["max_shrinking_steps"] >= 0 and
      record["generated"] <= limits["max_runs"] and
      record["shrink_attempts"] <= limits["max_shrinking_steps"] and
      is_list(record["contracts"]) and record["contracts"] != [] and
      Enum.all?(record["contracts"], &(&1 in ids)) and
      is_list(record["declared_forced_cases"]) and
      Enum.all?(record["declared_forced_cases"], &valid_case?(&1, record["contracts"], ids)) and
      is_map(record["observations"]) and
      Enum.all?(record["observations"], fn {name, count} ->
        is_binary(name) and is_integer(count) and count > 0 and
          count <= record["generated"] + record["examples"] + record["replayed"]
      end) and
      (record["outcome"] != "passed" or
         (record["generated"] > 0 and map_size(record["observations"]) > 0))
  end

  defp measurement_errors(tests, measurements) do
    owners =
      Enum.filter(
        tests,
        &(&1.result == "passed" and (&1.suite == "fuzz" or not is_nil(&1.measurement_id)))
      )

    missing =
      for test <- owners,
          not Enum.any?(measurements, fn record ->
            record["id"] == test.measurement_id and record["variant"] == test.suite and
              record["outcome"] == "passed" and record["contracts"] == test.contracts and
              record["declared_forced_cases"] == test.declared_forced_cases
          end),
          do: "missing or mismatched measurements: #{test.test}"

    failed =
      for record <- measurements,
          record["outcome"] != "passed",
          do: "measurement did not pass: #{record["id"]}"

    orphaned =
      for record <- measurements,
          not Enum.any?(
            owners,
            &(&1.measurement_id == record["id"] and &1.suite == record["variant"])
          ),
          do: "measurement has no passed owner: #{record["id"]}"

    duplicates =
      measurements
      |> Enum.frequencies_by(&{&1["id"], &1["variant"]})
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, _count} -> "duplicate measurements: #{inspect(key)}" end)

    missing ++ failed ++ orphaned ++ duplicates
  end

  defp invalid_case_ids(records, ids) do
    for record <- records,
        id <- record.declared_forced_cases,
        not valid_case?(id, record.contracts, ids),
        uniq: true,
        do: id
  end

  defp valid_case?(id, contracts, ids) do
    case if(is_binary(id), do: String.split(id, "/", parts: 2), else: []) do
      [contract, name] -> name != "" and contract in contracts and contract in ids
      _ -> false
    end
  end

  defp action_flow_test?(test) do
    test.module
    |> inspect()
    |> String.starts_with?("JidoTest.Property.ActionFlow.")
  end

  defp contract_ids(root) do
    register = Path.join(root, "guides/public-contracts.md")

    if File.regular?(register) do
      register
      |> File.read!()
      |> then(&Regex.scan(~r/^\| ([A-Z]+-\d+) \|/m, &1))
      |> Enum.map(&List.last/1)
    else
      @required_contract_ids
    end
  end

  defp git_metadata(root) do
    with git when is_binary(git) <- System.find_executable("git"),
         {top, 0} <-
           System.cmd(git, ["rev-parse", "--show-toplevel"], cd: root, stderr_to_stdout: true),
         true <- Path.expand(String.trim(top)) == Path.expand(root),
         {revision, 0} <-
           System.cmd(git, ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true),
         {status, 0} <-
           System.cmd(git, ["status", "--porcelain"], cd: root, stderr_to_stdout: true) do
      %{revision: String.trim(revision), working_tree_dirty: status != ""}
    else
      _ -> %{revision: nil, working_tree_dirty: nil}
    end
  end

  defp report_path, do: Path.join(Mix.Project.build_path(), "action-flow-property-report.json")

  defp write!(path, report) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path <> ".tmp", JSON.encode!(report))
    File.rename!(path <> ".tmp", path)
  end

  defp result(nil), do: "passed"
  defp result({:failed, _}), do: "failed"
  defp result({:excluded, _}), do: "excluded"
  defp result({:skipped, _}), do: "skipped"
  defp result(_), do: "invalid"
end
