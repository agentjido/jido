defmodule JidoTest.Property.Fuzz do
  @moduledoc false

  # A small adapter for public StreamData.check_all/3. StreamData owns generation
  # and shrinking. Inputs and returned observation names must be JSON data.
  def check(id, generator, options, assertion) do
    unless Regex.match?(~r/^[a-z][a-z0-9_]+$/, id), do: raise(ArgumentError, "invalid fuzz ID")

    if options[:property] && options[:fuzz],
      do: raise(ArgumentError, "property and fuzz tags must not overlap; use ExUnit test/3")

    root = Keyword.get(options, :root, Mix.Project.build_path())
    report_path = Path.join(root, "property-report.json")
    report = read_report(root)

    report =
      if report["status"] == "incomplete",
        do: report,
        else:
          JidoTest.Property.Report.prepare!(report_path,
            root: Keyword.get(options, :source_root, Path.expand("../../..", __DIR__))
          )

    key = {__MODULE__, make_ref()}
    seed = Keyword.get(options, :seed, ExUnit.configuration()[:seed])
    variant = if options[:fuzz], do: :fuzz, else: :property

    limits =
      Keyword.merge(
        [max_runs: 40, max_run_time: 10_000, max_shrinking_steps: 200],
        Keyword.take(options, [:max_runs, :max_run_time, :max_shrinking_steps])
      )

    for {name, value} <- limits do
      minimum = if name == :max_shrinking_steps, do: 0, else: 1

      unless is_integer(value) and value >= minimum,
        do: raise(ArgumentError, "invalid fuzz budget #{name}: #{inspect(value)}")
    end

    run_id = report["run_id"] || report[:run_id]
    started = System.monotonic_time(:millisecond)

    stats = %{
      id: id,
      run_id: run_id,
      variant: variant,
      seed: seed,
      contracts: Keyword.get(options, :contracts, []),
      declared_forced_cases: Keyword.get(options, :contract_cases, []),
      test_timeout: Keyword.get(options, :timeout),
      limits: Map.new(limits),
      generated: 0,
      shrink_attempts: 0,
      replayed: 0,
      examples: 0,
      confirmations: 0,
      observations: %{},
      source:
        Map.take(read_report(root), [
          "revision",
          "working_tree_dirty",
          "source_digest",
          "dependencies",
          "runtime",
          "elixir",
          "otp",
          "otp_version",
          "zoi",
          "stream_data"
        ]),
      outcome: "incomplete"
    }

    Process.put(key, {stats, :generate})

    measurement = Path.join([root, "property-fuzz", run_id, "#{id}-#{variant}.json"])

    try do
      write!(measurement, stats)

      for input <- Keyword.get(options, :examples, []) do
        run_fixed!(key, :examples, input, assertion)
      end

      corpus = Path.wildcard(Path.expand("../corpus/#{id}/*.json", __DIR__))

      set_phase(key, :replay_load)
      inputs = saved_inputs(root, id, Keyword.get(options, :corpus, corpus))

      for input <- inputs do
        run_fixed!(key, :replayed, input, assertion)
      end

      set_phase(key, :generate)

      result =
        StreamData.check_all(
          generator,
          [initial_seed: {seed, :erlang.phash2(id), 0}] ++ limits,
          fn input ->
            {_stats, phase} = Process.get(key)
            result = attempt(key, phase, input, assertion)
            if match?({:error, _}, result), do: set_phase(key, :shrink)
            result
          end
        )

      case result do
        {:ok, _} ->
          update(key, &%{&1 | outcome: "passed"})

        {:error, failure} ->
          reduced = failure.shrunk_failure
          path = save_failure(root, id, seed, reduced, stats.contracts)

          update(
            key,
            &Map.merge(&1, %{
              outcome: "failed",
              counterexample: path,
              shrink_nodes_visited: failure.nodes_visited
            })
          )

          # Check the same reduced input once more. An unstable replay is still a failure.
          stable? =
            case attempt(key, :confirmations, reduced.input, assertion) do
              {:error, again} -> signature(again) == signature(reduced)
              {:ok, _} -> false
            end

          update(key, &Map.put(&1, :reproduced, stable?))

          IO.puts(
            :stderr,
            "Fuzz #{id} failed; reduced input: #{inspect(reduced.input)}; replay: #{path}; stable: #{stable?}"
          )

          :erlang.raise(reduced.kind, reduced.reason, reduced.stacktrace)
      end
    catch
      kind, reason ->
        {_stats, phase} = Process.get(key)

        update(key, fn stats ->
          if stats.outcome == "incomplete",
            do: Map.merge(stats, %{outcome: "failed", failed_phase: phase}),
            else: stats
        end)

        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      {stats, _phase} = Process.delete(key)
      stats = Map.put(stats, :elapsed_ms, System.monotonic_time(:millisecond) - started)

      write!(
        measurement,
        stats
      )
    end

    :ok
  end

  defp run_fixed!(key, phase, input, assertion) do
    case attempt(key, phase, input, assertion) do
      {:ok, _} ->
        :ok

      {:error, failure} ->
        update(
          key,
          &Map.merge(&1, %{
            outcome: "failed",
            failed_phase: phase,
            failed_input: serializable_value(input)
          })
        )

        :erlang.raise(failure.kind, failure.reason, failure.stacktrace)
    end
  end

  defp attempt(key, phase, input, assertion) do
    field =
      case phase do
        :generate -> :generated
        :shrink -> :shrink_attempts
        other -> other
      end

    update(key, &Map.update!(&1, field, fn n -> n + 1 end))

    try do
      serializable!(input)
      observations = assertion.(input)

      unless is_list(observations) and not List.improper?(observations) and
               Enum.all?(observations, &is_binary/1),
             do: raise(ArgumentError, "fuzz assertions must return a list of observation names")

      # Count passing discovery/examples/replays, never successful shrink candidates.
      if phase not in [:shrink, :confirmations] do
        update(key, fn stats ->
          observations =
            Enum.reduce(Enum.uniq(observations), stats.observations, fn event, counts ->
              Map.update(counts, event, 1, &(&1 + 1))
            end)

          %{stats | observations: observations}
        end)
      end

      {:ok, nil}
    catch
      kind, reason ->
        {:error, %{input: input, kind: kind, reason: reason, stacktrace: __STACKTRACE__}}
    end
  end

  defp saved_inputs(root, id, corpus) do
    generated = Path.wildcard(Path.join([root, "property-counterexamples", id, "*.json"]))

    Enum.map(Enum.sort(Enum.uniq(corpus ++ generated)), fn path ->
      with {:ok, data} <- File.read(path),
           {:ok, %{"format" => 1, "property" => ^id, "input" => input}} <- JSON.decode(data) do
        input
      else
        _ -> raise ArgumentError, "invalid fuzz replay file: #{path}"
      end
    end)
  end

  defp save_failure(root, id, seed, failure, contracts) do
    # Do not persist opaque BEAM resources or rely on atom creation when replaying.
    input = failure.input

    serializable!(input)

    hash = :crypto.hash(:sha256, JSON.encode!(input)) |> Base.encode16(case: :lower)
    path = Path.join([root, "property-counterexamples", id, hash <> ".json"])

    write!(path, %{
      format: 1,
      property: id,
      contracts: contracts,
      input: input,
      seed: seed,
      elixir: System.version(),
      otp: System.otp_release(),
      stream_data: to_string(Application.spec(:stream_data, :vsn)),
      source:
        Map.take(read_report(root), [
          "revision",
          "working_tree_dirty",
          "source_digest",
          "dependencies",
          "runtime",
          "elixir",
          "otp",
          "otp_version",
          "zoi",
          "stream_data",
          "run_id"
        ]),
      failure: Exception.format_banner(failure.kind, failure.reason, failure.stacktrace)
    })

    path
  end

  defp signature(failure),
    do: {failure.kind, Exception.format_banner(failure.kind, failure.reason, [])}

  defp update(key, fun) do
    {stats, phase} = Process.get(key)
    Process.put(key, {fun.(stats), phase})
  end

  defp set_phase(key, phase) do
    {stats, _} = Process.get(key)
    Process.put(key, {stats, phase})
  end

  defp read_report(root) do
    with {:ok, data} <- File.read(Path.join(root, "property-report.json")),
         {:ok, report} <- JSON.decode(data) do
      report
    else
      _ -> %{}
    end
  end

  defp serializable!(input) do
    unless JSON.decode!(JSON.encode!(input)) === input,
      do: raise(ArgumentError, "fuzz input must round-trip as plain JSON data")

    :ok
  rescue
    _error ->
      reraise ArgumentError.exception("fuzz input must round-trip as plain JSON data"),
              __STACKTRACE__
  end

  defp serializable_value(input) do
    serializable!(input)
    input
  rescue
    _ -> "unsupported-input"
  end

  defp write!(path, value), do: JidoTest.Property.Report.write!(path, value)
end
