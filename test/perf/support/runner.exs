Code.require_file("result.exs", __DIR__)

defmodule Jido.Test.Perf.Runner do
  @moduledoc false

  alias Jido.Test.Perf.Result

  @profiles ~w(quick standard stress)
  @root Path.expand("tmp/perf")
  @script_paths %{
    "dsl_compile" => "test/perf/jido_flow/dsl_compile.exs",
    "flow_compile" => "test/perf/jido_flow/flow_compile.exs",
    "flow_run" => "test/perf/jido_exec/flow_run.exs",
    "react_stress" => "test/perf/jido_ai/react_stress.exs"
  }

  def options!(argv, suite) do
    {options, arguments, invalid} =
      OptionParser.parse(argv, strict: [profile: :string, output: :string])

    if arguments != [] or invalid != [], do: usage_error!(suite)

    profile = Keyword.get(options, :profile, "quick")
    if profile not in @profiles, do: usage_error!(suite)

    default = Path.join(@root, "#{suite}-#{profile}.json")
    output = options |> Keyword.get(:output, default) |> Path.expand()

    unless String.starts_with?(output, @root <> "/") do
      raise ArgumentError, "benchmark output must be under tmp/perf"
    end

    %{profile: profile, output: output}
  end

  def profile!(profile, values), do: Map.fetch!(values, profile)

  def await_task_children!(expected, attempts \\ 100)
  def await_task_children!(expected, 0), do: check_task_children!(expected)

  def await_task_children!(expected, attempts) do
    if task_children() == expected do
      :ok
    else
      Process.sleep(10)
      await_task_children!(expected, attempts - 1)
    end
  end

  def task_children do
    Jido.Exec.TaskSupervisor
    |> Task.Supervisor.children()
    |> MapSet.new()
  end

  def measure!(name, operation, check, settings) do
    operation.() |> check.()

    for _sample <- 1..settings.warmup do
      operation.() |> check.()
    end

    raw =
      for _sample <- 1..settings.samples do
        reductions_before = :erlang.statistics(:reductions) |> elem(0)
        started = System.monotonic_time()
        result = operation.()
        elapsed = System.monotonic_time() - started
        reductions_after = :erlang.statistics(:reductions) |> elem(0)
        check.(result)

        %{
          elapsed_us: System.convert_time_unit(elapsed, :native, :microsecond),
          system_reductions: reductions_after - reductions_before
        }
      end

    %{
      id: name,
      validated_before_measurement: true,
      samples: settings.samples,
      raw: raw,
      elapsed_us: distribution(raw, :elapsed_us),
      system_reductions: distribution(raw, :system_reductions)
    }
  end

  def report!(suite, options, settings, cases, extra \\ %{}) do
    report =
      Map.merge(
        %{
          benchmark_result_schema_version: Result.schema_version(),
          schema_version: 1,
          metadata: Result.metadata(suite, options.profile),
          suite: suite,
          source: source(),
          environment: environment(),
          settings: Map.put(settings, :profile, options.profile),
          method:
            "Validate one result before measurement. Validate every measured result and wait for owned execution tasks to stop. Timing has no pass limit.",
          cases: cases
        },
        extra
      )

    Result.validate!(report)

    File.mkdir_p!(Path.dirname(options.output))
    File.write!(options.output, [JSON.encode!(report), "\n"])
    IO.puts("report=#{options.output}")
    report
  end

  defp distribution(rows, key) do
    values = rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sort()
    middle = div(length(values), 2)

    median =
      if rem(length(values), 2) == 1,
        do: Enum.at(values, middle),
        else: div(Enum.at(values, middle - 1) + Enum.at(values, middle), 2)

    %{
      min: hd(values),
      median: median,
      p95: Enum.at(values, max(ceil(length(values) * 0.95) - 1, 0)),
      max: List.last(values)
    }
  end

  defp source do
    files =
      (Path.wildcard("lib/**/*") ++
         Path.wildcard("test/perf/**/*") ++
         ["test/perf/jido_ai/react_memory.exs", "mix.exs", "mix.lock"])
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    digest =
      files
      |> Enum.map(&[&1, <<0>>, File.read!(&1), <<0>>])
      |> hash()

    %{
      commit: command("git", ["rev-parse", "HEAD"]),
      checkout_dirty: command("git", ["status", "--porcelain"]) != "",
      sha256: digest,
      files: length(files)
    }
  end

  defp environment do
    %{
      elixir: System.version(),
      otp: System.otp_release(),
      erts: :erlang.system_info(:version) |> List.to_string(),
      architecture: :erlang.system_info(:system_architecture) |> List.to_string(),
      mix_env: Mix.env(),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      dependency_lock_sha256: File.read!("mix.lock") |> hash()
    }
  end

  defp check_task_children!(expected) do
    actual = task_children()
    if actual != expected, do: raise("execution tasks remain active after the benchmark case")
    :ok
  end

  defp command(executable, arguments) do
    case System.cmd(executable, arguments, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _error -> "unavailable"
    end
  end

  defp hash(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp usage_error!(suite) do
    raise ArgumentError,
          "usage: mix run #{Map.fetch!(@script_paths, suite)} " <>
            "--profile quick|standard|stress " <>
            "[--output tmp/perf/FILE.json]"
  end
end
