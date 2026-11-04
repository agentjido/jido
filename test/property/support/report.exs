Code.require_file("config.exs", __DIR__)

defmodule JidoTest.Property.Report do
  @moduledoc false
  use GenServer

  alias JidoTest.Property.Config

  @root Path.expand("../../..", __DIR__)

  def check!(options \\ []) do
    path = Keyword.get(options, :path, Config.report_path())
    full? = Keyword.get(options, :full, false)
    suite = Keyword.get(options, :suite)
    configs = Keyword.get(options, :configs, Config.families())
    report = path |> File.read!() |> JSON.decode!()

    if report["status"] != "finished" or report["outcome"] == "failed" do
      raise "property report did not pass: #{inspect(report["outcome"])}"
    end

    if full? do
      missing_families = Map.keys(configs) -- Map.keys(report["families"] || %{})

      if missing_families != [] do
        raise "missing property families: #{Enum.join(missing_families, ", ")}"
      end

      if suite == :fuzz do
        completed =
          for {_family, result} <- report["families"],
              measurement <- result["measurements"],
              measurement["variant"] == "fuzz" and measurement["outcome"] == "passed",
              do: {measurement["family"], measurement["id"]}

        required =
          for {family, config} <- configs, id <- config.fuzz_ids, do: {family, id}

        missing = required -- completed
        if missing != [], do: raise("missing fuzz measurements: #{inspect(missing)}")
      end
    end

    :ok
  end

  def fuzz_ids do
    Map.new(Config.families(), fn {family, config} -> {family, Enum.sort(config.fuzz_ids)} end)
  end

  # Invalidate old evidence before test files compile.
  def prepare!(path \\ Config.report_path()) do
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
    path = Keyword.get(options, :path, Config.report_path())
    root = Keyword.get(options, :root, @root)
    configs = Keyword.get(options, :configs, Config.families())

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
       configs: configs,
       records: [],
       failed?: false
     }}
  end

  @impl true
  def handle_cast({:test_finished, test}, state) do
    result = result(test.state)
    state = %{state | failed?: state.failed? or result in ["failed", "invalid"]}

    if test.tags[:property] || test.tags[:fuzz] do
      case family_for_module(test.module, state.configs) do
        nil ->
          {:noreply, state}

        family ->
          record = %{
            family: family,
            test: "#{inspect(test.module)}: #{test.name}",
            suite: if(test.tags[:fuzz], do: "fuzz", else: "property"),
            measurement_id: test.tags[:fuzz_id],
            result: result
          }

          {:noreply, %{state | records: [record | state.records]}}
      end
    else
      {:noreply, state}
    end
  end

  def handle_cast({:suite_finished, _times}, state) do
    {measurements, artifact_errors} = measurement_records(state)

    family_ids =
      (Enum.map(state.records, & &1.family) ++ Enum.map(measurements, & &1["family"]))
      |> Enum.uniq()
      |> Enum.sort()

    families =
      Map.new(family_ids, fn family ->
        records = Enum.filter(state.records, &(&1.family == family))
        family_measurements = Enum.filter(measurements, &(&1["family"] == family))
        family_artifacts = Enum.filter(artifact_errors, &(&1[:family] == family))
        errors = measurement_errors(family, records, family_measurements, state.configs)

        outcome =
          if Enum.any?(records, &(&1.result in ["failed", "invalid"])) or errors != [] or
               family_artifacts != [],
             do: "failed",
             else: "passed"

        {family,
         %{
           outcome: outcome,
           tests: Enum.sort_by(records, & &1.test),
           measurements: family_measurements,
           validation_errors: errors,
           artifact_errors: family_artifacts
         }}
      end)

    outcome =
      cond do
        state.failed? or artifact_errors != [] or
            Enum.any?(families, fn {_id, result} -> result.outcome == "failed" end) ->
          "failed"

        map_size(families) == 0 ->
          "no_evidence"

        true ->
          "passed"
      end

    report =
      Map.merge(state.metadata, %{
        status: "finished",
        finished_at: DateTime.to_iso8601(DateTime.utc_now()),
        outcome: outcome,
        families: families,
        artifact_errors: artifact_errors
      })

    write!(state.path, report)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp measurement_records(state) do
    Path.join([Path.dirname(state.path), "property-fuzz", state.metadata.run_id, "*", "*.json"])
    |> Path.wildcard()
    |> Enum.reduce({[], []}, fn path, {records, errors} ->
      with {:ok, data} <- File.read(path),
           {:ok, record} when is_map(record) <- JSON.decode(data) do
        family = record["family"]

        cond do
          record["run_id"] != state.metadata.run_id ->
            {records, errors}

          valid_measurement?(record, state.configs) ->
            {[record | records], errors}

          true ->
            {records, [%{path: path, family: family, error: "invalid fuzz measurement"} | errors]}
        end
      else
        error -> {records, [%{path: path, family: nil, error: inspect(error)} | errors]}
      end
    end)
    |> then(fn {records, errors} ->
      {
        Enum.sort_by(records, &{&1["family"], &1["id"], &1["variant"]}),
        Enum.sort_by(errors, & &1.path)
      }
    end)
  end

  defp valid_measurement?(record, configs) do
    limits = record["limits"]
    counts = ~w(generated examples replayed shrink_attempts confirmations elapsed_ms)
    family = configs[record["family"]]

    is_map(family) and record["id"] in family.fuzz_ids and
      record["variant"] in ["fuzz", "property"] and
      record["outcome"] in ["passed", "failed", "incomplete"] and
      is_integer(record["seed"]) and is_integer(record["test_timeout"]) and
      record["test_timeout"] > 0 and
      Enum.all?(counts, &(is_integer(record[&1]) and record[&1] >= 0)) and
      is_map(limits) and is_integer(limits["max_runs"]) and limits["max_runs"] > 0 and
      is_integer(limits["max_run_time"]) and limits["max_run_time"] > 0 and
      is_integer(limits["max_shrinking_steps"]) and limits["max_shrinking_steps"] >= 0 and
      record["generated"] <= limits["max_runs"] and
      record["shrink_attempts"] <= limits["max_shrinking_steps"] and
      is_map(record["observations"]) and
      Enum.all?(record["observations"], fn {name, count} ->
        is_binary(name) and is_integer(count) and count > 0 and
          count <= record["generated"] + record["examples"] + record["replayed"]
      end) and
      (record["outcome"] != "passed" or
         (record["generated"] > 0 and map_size(record["observations"]) > 0))
  end

  defp measurement_errors(family, tests, measurements, configs) do
    owners = Enum.filter(tests, &(&1.result == "passed" and not is_nil(&1.measurement_id)))

    missing_ids =
      for test <- tests,
          test.suite == "fuzz" and is_nil(test.measurement_id),
          do: "fuzz test has no measurement ID: #{test.test}"

    missing =
      for test <- owners,
          not Enum.any?(measurements, fn record ->
            record["id"] == test.measurement_id and record["variant"] == test.suite and
              record["outcome"] == "passed"
          end),
          do: "missing or failed measurement: #{test.test}"

    failed =
      for record <- measurements,
          record["outcome"] != "passed",
          do: "measurement did not pass: #{record["id"]}"

    orphaned =
      for record <- measurements,
          not Enum.any?(owners, &(&1.measurement_id == record["id"] and &1.suite == record["variant"])),
          do: "measurement has no passed owner: #{record["id"]}"

    duplicates =
      measurements
      |> Enum.frequencies_by(&{&1["id"], &1["variant"]})
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(fn {key, _count} -> "duplicate measurements: #{inspect(key)}" end)

    missing_observations =
      for record <- measurements,
          observation <- get_in(configs, [family, :required_observations, record["id"]]) || [],
          not Map.has_key?(record["observations"], observation),
          do: "measurement #{record["id"]} missed observation #{observation}"

    missing_ids ++ missing ++ failed ++ orphaned ++ duplicates ++ missing_observations
  end

  defp family_for_module(module, configs) do
    name = inspect(module)

    Enum.find_value(configs, fn {family, config} ->
      if Enum.any?(config.module_prefixes, &String.starts_with?(name, &1)), do: family
    end)
  end

  defp git_metadata(root) do
    with git when is_binary(git) <- System.find_executable("git"),
         {top, 0} <- System.cmd(git, ["rev-parse", "--show-toplevel"], cd: root, stderr_to_stdout: true),
         true <- Path.expand(String.trim(top)) == Path.expand(root),
         {revision, 0} <- System.cmd(git, ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true),
         {status, 0} <- System.cmd(git, ["status", "--porcelain"], cd: root, stderr_to_stdout: true) do
      %{revision: String.trim(revision), working_tree_dirty: status != ""}
    else
      _ -> %{revision: nil, working_tree_dirty: nil}
    end
  end

  defp source_digest(root) do
    paths = [
      "mix.exs",
      "mix.lock",
      "lib/**/*.{ex,exs}",
      "test/**/*.{ex,exs,json}",
      "config/**/*.{ex,exs}",
      "guides/*.md"
    ]

    files = paths |> Enum.flat_map(&Path.wildcard(Path.join(root, &1))) |> Enum.uniq() |> Enum.sort()

    digest =
      Enum.reduce(files, :crypto.hash_init(:sha256), fn path, hash ->
        :crypto.hash_update(hash, [Path.relative_to(path, root), <<0>>, File.read!(path), <<0>>])
      end)

    digest |> :crypto.hash_final() |> Base.encode16(case: :lower)
  end

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
