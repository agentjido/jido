Code.require_file("config.exs", __DIR__)

defmodule Jido.Test.Property.Fuzz do
  @moduledoc false

  alias Jido.Test.Property.Config

  # StreamData owns generation and shrinking. Inputs and observation names must
  # use JSON-compatible data so a reduced failure can be replayed.
  def check(id, generator, options, assertion) do
    unless Regex.match?(~r/^[a-z][a-z0-9_]+$/, id), do: raise(ArgumentError, "invalid fuzz ID")

    if options[:property] && options[:fuzz],
      do: raise(ArgumentError, "property and fuzz tags must not overlap; use ExUnit test/3")

    family = Keyword.get(options, :family) || Config.family_for_measurement(id) || "test"
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

    root = Keyword.get(options, :root, Mix.Project.build_path())
    run_id = report_run_id(root)
    started = System.monotonic_time(:millisecond)

    stats = %{
      id: id,
      family: family,
      run_id: run_id,
      variant: variant,
      seed: seed,
      test_timeout: Keyword.get(options, :timeout),
      limits: Map.new(limits),
      generated: 0,
      shrink_attempts: 0,
      replayed: 0,
      examples: 0,
      confirmations: 0,
      observations: %{},
      outcome: "incomplete"
    }

    Process.put(key, {stats, :generate})

    try do
      for input <- Keyword.get(options, :examples, []) do
        run_fixed!(key, :examples, input, assertion)
      end

      corpus = Keyword.get(options, :corpus, Config.corpus(family, id))

      set_phase(key, :replay_load)
      inputs = saved_inputs(root, family, id, corpus)

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
          path = save_failure(root, family, id, seed, reduced)

          update(
            key,
            &Map.merge(&1, %{
              outcome: "failed",
              counterexample: path,
              shrink_nodes_visited: failure.nodes_visited
            })
          )

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
      write!(Config.measurement_path(root, run_id, family, id, variant), stats)
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
          &Map.merge(&1, %{outcome: "failed", failed_phase: phase, failed_input: input})
        )

        :erlang.raise(failure.kind, failure.reason, failure.stacktrace)
    end
  end

  defp attempt(key, phase, input, assertion) do
    field = if phase == :generate, do: :generated, else: if(phase == :shrink, do: :shrink_attempts, else: phase)
    update(key, &Map.update!(&1, field, fn n -> n + 1 end))

    try do
      observations = assertion.(input)

      unless is_list(observations) and Enum.all?(observations, &is_binary/1),
        do: raise(ArgumentError, "fuzz assertions must return a list of observation names")

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

  defp saved_inputs(root, family, id, corpus) do
    generated = Path.wildcard(Path.join(Config.counterexample_dir(root, family, id), "*.json"))

    Enum.map(Enum.sort(Enum.uniq(corpus ++ generated)), fn path ->
      with {:ok, data} <- File.read(path),
           {:ok, %{"format" => 1, "property" => ^id, "input" => input}} <- JSON.decode(data) do
        input
      else
        _ -> raise ArgumentError, "invalid fuzz replay file: #{path}"
      end
    end)
  end

  defp save_failure(root, family, id, seed, failure) do
    input = failure.input

    unless JSON.decode!(JSON.encode!(input)) == input,
      do: raise(ArgumentError, "fuzz replay input must round-trip as plain JSON data")

    hash = :crypto.hash(:sha256, JSON.encode!(input)) |> Base.encode16(case: :lower)
    path = Path.join(Config.counterexample_dir(root, family, id), hash <> ".json")

    write!(path, %{
      format: 1,
      property: id,
      family: family,
      input: input,
      seed: seed,
      elixir: System.version(),
      otp: System.otp_release(),
      stream_data: to_string(Application.spec(:stream_data, :vsn)),
      source: Map.take(read_report(root), ["revision", "working_tree_dirty", "source_digest", "run_id"]),
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

  defp report_run_id(root), do: read_report(root)["run_id"]

  defp read_report(root) do
    with {:ok, data} <- File.read(Config.report_path(root)),
         {:ok, report} <- JSON.decode(data) do
      report
    else
      _ -> %{}
    end
  end

  defp write!(path, value) do
    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".#{System.pid()}-#{System.unique_integer([:positive])}.tmp"

    try do
      File.write!(temporary, JSON.encode!(value))
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end
end
