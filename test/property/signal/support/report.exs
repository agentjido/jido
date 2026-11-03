defmodule JidoTest.Property.Signal.Report do
  @moduledoc false
  use GenServer

  @root Path.expand("../../../..", __DIR__)
  @required_contract_ids ~w(
    BUS-001 BUS-002 BUS-003 CAT-001 CTX-001 DISP-001 DISP-002 DUR-001 DUR-002
    ID-001 OBS-001 ROUTE-001 ROUTE-002 ROUTE-003 SIG-001 STORE-001 STORE-002 TRACE-001 WIRE-001 WIRE-002
  )
  @required_case_ids ~w(
    bus_histories bus_observations catalog_boundaries dispatch_sequences
    durable_store_faults envelope_wire memory_histories pid_lifecycles routing_model trace_ids wire_mutations
  )

  def check!(path \\ report_path()) do
    report = path |> File.read!() |> JSON.decode!()

    unless report["status"] == "finished" and report["outcome"] == "passed",
      do: raise("Signal property report did not pass: #{inspect(report["outcome"])}")

    missing = report["required_case_ids_without_measurement"] || []
    if missing != [], do: raise("missing Signal property cases: #{Enum.join(missing, ", ")}")
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
    required_case_ids = Keyword.get(options, :required_case_ids, @required_case_ids)
    strict? = Keyword.get(options, :strict, path == report_path())

    metadata =
      prepare!(path)
      |> Map.merge(git_metadata(root))
      |> Map.merge(%{
        package_version: Mix.Project.config()[:version],
        elixir: System.version(),
        otp: System.otp_release(),
        stream_data: to_string(Application.spec(:stream_data, :vsn)),
        source_digest: source_digest(root),
        exunit_seed: ExUnit.configuration()[:seed],
        selection: %{
          include: inspect(ExUnit.configuration()[:include]),
          exclude: inspect(ExUnit.configuration()[:exclude])
        }
      })

    write!(path, metadata)

    {:ok,
     %{
       path: path,
       metadata: metadata,
       ids: ids,
       required_case_ids: required_case_ids,
       strict?: strict?,
       records: [],
       failed?: false
     }}
  end

  @impl true
  def handle_cast({:test_finished, test}, state) do
    result = result(test.state)
    state = %{state | failed?: state.failed? or result in ["failed", "invalid"]}

    if test.tags[:property] || test.tags[:fuzz] do
      record = %{
        test: "#{inspect(test.module)}: #{test.name}",
        suite: if(test.tags[:fuzz], do: "fuzz", else: "property"),
        contracts: Map.get(test.tags, :contracts, []),
        declared_forced_cases: Map.get(test.tags, :contract_cases, []),
        result: result
      }

      {:noreply, %{state | records: [record | state.records]}}
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
    measured_case_ids = fuzz |> Enum.map(& &1["id"]) |> Enum.uniq()
    missing_case_ids = Enum.sort(state.required_case_ids -- measured_case_ids)

    report =
      Map.merge(state.metadata, %{
        status: "finished",
        finished_at: DateTime.to_iso8601(DateTime.utc_now()),
        outcome:
          cond do
            state.failed? or artifact_errors != [] or (state.strict? and missing_case_ids != []) -> "failed"
            evidenced == [] -> "no_evidence"
            true -> "passed"
          end,
        contracts_with_passed_evidence: evidenced,
        declared_forced_cases_in_passed_tests: cases,
        contracts_without_passed_evidence: Enum.sort(state.ids -- evidenced),
        required_case_ids_without_measurement: missing_case_ids,
        contract_evidence_by_suite:
          Map.new(["property", "fuzz"], fn suite ->
            {suite, evidence(Enum.filter(state.records, &(&1.suite == suite)), state.ids)}
          end),
        unknown_contract_ids: Enum.sort(declared -- state.ids),
        invalid_case_ids: invalid_case_ids(state.records, state.ids),
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
    Path.join([Path.dirname(state.path), "property-fuzz", state.metadata.run_id, "*.json"])
    |> Path.wildcard()
    |> Enum.reduce({[], []}, fn path, {records, errors} ->
      with {:ok, data} <- File.read(path),
           {:ok, record} when is_map(record) <- JSON.decode(data) do
        if record["run_id"] == state.metadata.run_id,
          do: {[record | records], errors},
          else: {records, errors}
      else
        error -> {records, [%{path: path, error: inspect(error)} | errors]}
      end
    end)
    |> then(fn {records, errors} ->
      {Enum.sort_by(records, &{&1["id"], &1["variant"]}), Enum.sort_by(errors, & &1.path)}
    end)
  end

  defp invalid_case_ids(records, ids) do
    for record <- records,
        id <- record.declared_forced_cases,
        not valid_case?(id, record.contracts, ids),
        uniq: true,
        do: id
  end

  defp contract_ids(root) do
    path = Path.join(root, "guides/public-contracts.md")

    if File.regular?(path) do
      path
      |> File.read!()
      |> then(&Regex.scan(~r/^\| ([A-Z]+-\d+) \|/m, &1))
      |> Enum.map(&List.last/1)
    else
      @required_contract_ids
    end
  end

  defp valid_case?(id, contracts, ids) do
    case String.split(id, "/", parts: 2) do
      [contract, name] -> name != "" and contract in contracts and contract in ids
      _ -> false
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

  # Include local edits and new test files. HEAD alone does not identify a dirty tree.
  defp source_digest(root) do
    paths = [
      "mix.exs",
      "mix.lock",
      "lib/**/*.{ex,exs}",
      "test/**/*.{ex,exs,json}",
      "config/**/*.{ex,exs}",
      "guides/*.md"
    ]

    files =
      paths |> Enum.flat_map(&Path.wildcard(Path.join(root, &1))) |> Enum.uniq() |> Enum.sort()

    digest =
      Enum.reduce(files, :crypto.hash_init(:sha256), fn path, hash ->
        :crypto.hash_update(hash, [Path.relative_to(path, root), <<0>>, File.read!(path), <<0>>])
      end)

    digest |> :crypto.hash_final() |> Base.encode16(case: :lower)
  end

  defp report_path, do: Path.join(Mix.Project.build_path(), "property-report.json")

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
