Code.require_file("fixtures.exs", __DIR__)
Code.require_file("measure.exs", __DIR__)
Code.require_file("report.exs", __DIR__)
Code.require_file("runtime_cases.exs", __DIR__)
Code.require_file("data_cases.exs", __DIR__)

defmodule JidoCoreBench.Suite do
  @moduledoc false
  alias JidoCoreBench.{Fixtures, Measure, Report, RuntimeCases, DataCases}

  def run(profile, filter \\ nil) do
    settings = Map.put(settings(profile), :filter, filter)

    workloads =
      workloads(profile) |> Enum.filter(&(is_nil(filter) or String.contains?(&1.id, filter)))

    if workloads == [], do: raise(ArgumentError, "no benchmark cases match the filter")
    ids = Enum.map(workloads, & &1.id)
    if length(Enum.uniq(ids)) != length(ids), do: raise("duplicate benchmark case IDs")
    {:ok, supervisor} = Jido.start_link(name: JidoCoreBench)

    try do
      IO.puts("Timing #{length(workloads)} core cases without tracing...")

      timings =
        Map.new(workloads, fn w ->
          {w.id, Measure.timing(w, settings.warmup, settings.samples)}
        end)

      IO.puts("Checking resources, retained terms, and process cleanup...")

      cases =
        Enum.map(workloads, fn w ->
          IO.puts("  #{w.id}")

          %{
            id: w.id,
            timing: Map.fetch!(timings, w.id),
            resources: Measure.resources(w, settings.resource_samples),
            retained_terms: Measure.retained(w)
          }
        end)

      %{
        schema_version: 1,
        source: source(),
        environment: environment(),
        settings: settings,
        recorded_at: DateTime.to_iso8601(DateTime.utc_now()),
        method:
          "core-v1: untraced operation time; traced caller and supervisor descendants; callback and result barriers; checked term transfer; explicit teardown",
        limitations: Report.limitations(),
        cases: cases
      }
    after
      Supervisor.stop(supervisor)
    end
  end

  def workloads(profile) do
    s = settings(profile)

    Fixtures.workloads(s.sizes, s.payloads) ++
      Fixtures.boundary_workloads() ++
      RuntimeCases.workloads(s.payloads) ++ DataCases.workloads(s.thread_sizes)
  end

  def write!(report, directory) do
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "report.json"), JSON.encode!(report))
    File.write!(Path.join(directory, "report.md"), Report.markdown(report))
  end

  def settings("smoke"),
    do: %{
      profile: "smoke",
      sizes: [1, 8],
      payloads: [:small],
      thread_sizes: [1, 32],
      warmup: 1,
      samples: 2,
      resource_samples: 1
    }

  def settings("short"),
    do: %{
      profile: "short",
      sizes: [1, 16],
      payloads: [:small, :large_map, :large_binary, :large_list],
      thread_sizes: [1, 100, 1_000],
      warmup: 5,
      samples: 30,
      resource_samples: 3
    }

  def settings("scale"),
    do: %{
      profile: "scale",
      sizes: [1, 16, 64],
      payloads: [:small, :large_map, :large_binary, :large_list],
      thread_sizes: [1, 100, 1_000, 10_000],
      warmup: 10,
      samples: 60,
      resource_samples: 5
    }

  def settings(_), do: raise(ArgumentError, "profile must be smoke, short, or scale")

  defp source do
    files = Path.wildcard(Path.expand("../**/*.exs", __DIR__)) |> Enum.sort()
    tool_sha = files |> Enum.map(&File.read!/1) |> hash()

    %{
      commit: command("git", ["rev-parse", "HEAD"]),
      runtime_dirty:
        command("git", ["status", "--porcelain", "--", "lib", "config", "mix.exs", "mix.lock"]) !=
          "",
      checkout_dirty: command("git", ["status", "--porcelain"]) != "",
      runtime_sha256:
        Path.wildcard("{lib,config}/**/*.{ex,exs}")
        |> Enum.sort()
        |> Enum.map(&File.read!/1)
        |> hash(),
      tool_sha256: tool_sha
    }
  end

  defp environment do
    %{
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release) |> List.to_string(),
      erts: :erlang.system_info(:system_version) |> List.to_string() |> String.trim(),
      os: command("uname", ["-srv"]),
      architecture: :erlang.system_info(:system_architecture) |> List.to_string(),
      cpu: cpu(),
      hostname: command("hostname", []),
      word_size: :erlang.system_info(:wordsize),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      logical_processors: :erlang.system_info(:logical_processors_available),
      mix_env: to_string(Mix.env()),
      logger_level: to_string(Logger.level()),
      dependency_lock_sha256: File.read!("mix.lock") |> hash()
    }
  end

  defp cpu do
    case :os.type() do
      {:unix, :darwin} ->
        command("sysctl", ["-n", "machdep.cpu.brand_string"])

      {:unix, :linux} ->
        case File.read("/proc/cpuinfo") do
          {:ok, text} ->
            text
            |> String.split("\n")
            |> Enum.find("unavailable", &String.starts_with?(&1, "model name"))

          _ ->
            "unavailable"
        end

      _ ->
        "unavailable"
    end
  end

  defp command(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> "unavailable"
    end
  rescue
    _ -> "unavailable"
  end

  defp hash(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
end
