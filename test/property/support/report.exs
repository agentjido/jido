defmodule JidoTest.Property.Report do
  @moduledoc false
  use GenServer

  @root Path.expand("../../..", __DIR__)

  # Write full incomplete evidence before register reads or test compilation.
  def prepare!(path \\ report_path(), options \\ []) do
    root = Keyword.get(options, :root, @root)

    metadata =
      %{
        status: "incomplete",
        started_at: DateTime.to_iso8601(DateTime.utc_now()),
        run_id: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false),
        package_version: Mix.Project.config()[:version],
        elixir: System.version(),
        otp: System.otp_release(),
        otp_version: otp_version(),
        runtime: :erlang.system_info(:system_version) |> to_string(),
        stream_data: application_version(:stream_data),
        zoi: application_version(:zoi),
        exunit_seed: ExUnit.configuration()[:seed],
        selection: %{
          include: inspect(ExUnit.configuration()[:include]),
          exclude: inspect(ExUnit.configuration()[:exclude])
        },
        source_digest: source_digest(root),
        dependencies: dependency_metadata(root)
      }
      |> Map.merge(git_metadata(root))

    write!(path, metadata)
    metadata
  end

  @impl true
  def init(options) do
    path = Keyword.get(options, :path, report_path())
    root = Keyword.get(options, :root, @root)
    metadata = prepare!(path, root: root)
    register = Keyword.get(options, :register, Path.join(root, "guides/public-contracts.md"))

    # A bad register leaves the complete incomplete record already on disk.
    text = File.read!(register)
    ids = Regex.scan(~r/^\| ([A-Z][A-Z0-9_-]*-\d+) \|/m, text) |> Enum.map(&List.last/1)
    if ids == [] or ids != Enum.uniq(ids), do: raise(ArgumentError, "invalid contract register")
    {:ok, %{path: path, metadata: metadata, ids: ids, records: [], failed?: false}}
  end

  @impl true
  def handle_cast({:test_finished, test}, state) do
    result = if test.tags[:property] && test.tags[:fuzz], do: "invalid", else: result(test.state)
    state = %{state | failed?: state.failed? or result in ["failed", "invalid"]}

    if test.tags[:property] || test.tags[:fuzz] do
      record = %{
        test: "#{inspect(test.module)}: #{test.name}",
        suite: if(test.tags[:fuzz], do: "fuzz", else: "property"),
        contracts: Map.get(test.tags, :contracts, []),
        declared_forced_cases: Map.get(test.tags, :contract_cases, []),
        fuzz_id: Map.get(test.tags, :fuzz_id),
        result: result
      }

      {:noreply, %{state | records: [record | state.records]}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:suite_finished, _times}, state) do
    {fuzz, artifact_errors} = fuzz_records(state)
    artifact_errors = artifact_errors ++ missing_artifacts(state.records, fuzz)
    unknown = Enum.sort(Enum.uniq(Enum.flat_map(state.records, & &1.contracts)) -- state.ids)
    invalid_cases = invalid_case_ids(state.records, state.ids)
    passed = Enum.filter(state.records, &passed_evidence?(&1, fuzz, state.ids))
    evidenced = passed |> Enum.flat_map(& &1.contracts) |> Enum.uniq() |> Enum.sort()
    cases = passed |> Enum.flat_map(& &1.declared_forced_cases) |> Enum.uniq() |> Enum.sort()

    report =
      Map.merge(state.metadata, %{
        status: "finished",
        finished_at: DateTime.to_iso8601(DateTime.utc_now()),
        outcome:
          cond do
            state.failed? or artifact_errors != [] or unknown != [] or invalid_cases != [] ->
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
            {suite, evidence(Enum.filter(state.records, &(&1.suite == suite)), state.ids, fuzz)}
          end),
        unknown_contract_ids: unknown,
        invalid_case_ids: invalid_cases,
        tests: Enum.sort_by(state.records, & &1.test),
        fuzz: fuzz,
        measurements_by_suite:
          Map.new(["property", "fuzz"], fn suite ->
            {suite, Enum.filter(fuzz, &(&1["variant"] == suite))}
          end),
        artifact_errors: artifact_errors
      })

    write!(state.path, report)
    {:noreply, state}
  end

  def handle_cast(_event, records), do: {:noreply, records}

  defp evidence(records, ids, artifacts) do
    passed = Enum.filter(records, &passed_evidence?(&1, artifacts, ids))
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

  defp passed_evidence?(record, artifacts, ids) do
    record.result == "passed" and
      Enum.all?(record.contracts, &(&1 in ids)) and
      Enum.all?(record.declared_forced_cases, &valid_case?(&1, record.contracts, ids)) and
      (is_nil(record.fuzz_id) or Enum.any?(artifacts, &artifact_matches?(record, &1)))
  end

  defp artifact_matches?(record, artifact) do
    artifact["id"] == record.fuzz_id and artifact["variant"] == record.suite and
      artifact["outcome"] == "passed" and
      artifact["contracts"] == record.contracts and
      artifact["declared_forced_cases"] == record.declared_forced_cases and
      is_integer(artifact["generated"]) and artifact["generated"] > 0
  end

  defp missing_artifacts(records, artifacts) do
    for record <- records,
        record.result == "passed" and not is_nil(record.fuzz_id),
        not Enum.any?(artifacts, &artifact_matches?(record, &1)),
        do: %{
          id: record.fuzz_id,
          suite: record.suite,
          error: "missing passed current-run measurement"
        }
  end

  defp invalid_case_ids(records, ids) do
    for record <- records,
        id <- record.declared_forced_cases,
        not valid_case?(id, record.contracts, ids),
        uniq: true,
        do: id
  end

  defp valid_case?(id, contracts, ids) do
    case String.split(id, "/", parts: 2) do
      [contract, name] -> name != "" and contract in contracts and contract in ids
      _ -> false
    end
  end

  defp git_metadata(root) do
    with true <- File.dir?(root),
         git when is_binary(git) <- System.find_executable("git"),
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

  defp otp_version do
    path =
      Path.join([to_string(:code.root_dir()), "releases", System.otp_release(), "OTP_VERSION"])

    case File.read(path) do
      {:ok, version} -> String.trim(version)
      _ -> nil
    end
  end

  defp application_version(application) do
    case Application.spec(application, :vsn) do
      nil -> nil
      version -> to_string(version)
    end
  end

  defp dependency_metadata(root) do
    Map.new([:jido_action, :jido_signal, :zoi, :stream_data], fn application ->
      declared = Enum.find(Mix.Project.config()[:deps] || [], &(elem(&1, 0) == application))

      opts =
        if is_tuple(declared) and is_list(elem(declared, tuple_size(declared) - 1)),
          do: elem(declared, tuple_size(declared) - 1),
          else: []

      declared_source = Path.expand(Keyword.get(opts, :path, "deps/#{application}"), root)
      source = loaded_source(application) || declared_source
      metadata = git_metadata(source)

      {application,
       Map.merge(metadata, %{
         version: application_version(application),
         declaration: inspect(declared),
         source_root: source,
         source_origin:
           if(loaded_source(application), do: "loaded module", else: "declared dependency"),
         source_present: File.dir?(source),
         source_digest: if(File.dir?(source), do: source_digest(source), else: nil)
       })}
    end)
  end

  defp loaded_source(application) when application in [:jido_action, :jido_signal] do
    module = if application == :jido_action, do: Jido.Action, else: Jido.Signal

    if :code.is_loaded(module) != false do
      case module.module_info(:compile)[:source] do
        nil -> nil
        source -> source |> to_string() |> Path.dirname() |> Path.dirname()
      end
    end
  end

  defp loaded_source(_application), do: nil

  # Include local edits and new test files. HEAD alone does not identify a dirty tree.
  defp source_digest(root) do
    paths = [
      "mix.exs",
      "mix.lock",
      "lib/**/*.{ex,exs}",
      "test/**/*.{ex,exs,json}",
      "examples/**/*.{ex,exs,json}",
      "config/**/*.{ex,exs}",
      "guides/**/*.{md,livemd}",
      "README.md",
      "AGENTS.md"
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

  @doc false
  def write!(path, report) do
    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".#{System.pid()}-#{System.unique_integer([:positive])}.tmp"

    try do
      File.write!(temporary, JSON.encode!(report))
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end

  defp result(nil), do: "passed"
  defp result({:failed, _}), do: "failed"
  defp result({:excluded, _}), do: "excluded"
  defp result({:skipped, _}), do: "skipped"
  defp result(_), do: "invalid"
end
