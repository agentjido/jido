Code.require_file("fixtures.exs", __DIR__)
Code.require_file("helpers.exs", __DIR__)
Code.require_file("signal_cases.exs", __DIR__)
Code.require_file("router_cases.exs", __DIR__)
Code.require_file("bus_cases.exs", __DIR__)
Code.require_file("selector_cases.exs", __DIR__)
Code.require_file("candidate_cases.exs", __DIR__)
Code.require_file("measure.exs", __DIR__)
Code.require_file("report.exs", __DIR__)
Code.require_file("../../support/result.exs", __DIR__)

defmodule Jido.Test.Perf.Signal.Suite do
  @moduledoc false
  alias Jido.Test.Perf.Signal.{Fixtures, Measure, Report}
  alias Jido.Test.Perf.Result

  def run(profile) do
    settings = settings(profile)
    growth_checks = check_growth!()
    workloads = workloads(profile)

    IO.puts("Timing #{length(workloads)} cases without tracing...")

    timings =
      Map.new(workloads, fn workload ->
        {workload.id, measure!(workload, fn -> Measure.timing(workload, settings.warmup, settings.samples) end)}
      end)

    IO.puts("Sampling memory and checking process cleanup in separate calls...")

    cases =
      Enum.map(workloads, fn workload ->
        %{
          id: workload.id,
          dimensions: workload.dimensions,
          timing: Map.fetch!(timings, workload.id),
          resources: measure!(workload, fn -> Measure.resources(workload) end),
          retained_term: Measure.term_size(workload.retained),
          activity: measure!(workload, fn -> Measure.activity(workload) end)
        }
      end)

    report = %{
      benchmark_result_schema_version: Result.schema_version(),
      schema_version: 2,
      metadata: Result.metadata("jido.signal", profile),
      suite: "jido.signal",
      source: source(),
      environment: environment(),
      settings: settings,
      growth_checks: growth_checks,
      recorded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      method:
        "untraced monotonic clock; caller reductions; separate traced setup/result barriers; monitored term transfer",
      limitations: Report.limitations(),
      cases: cases
    }

    Result.validate!(report)
  end

  def workloads("candidates"),
    do: Enum.flat_map([2, 32], &Jido.Test.Perf.Signal.CandidateCases.workloads/1)

  def workloads(profile) do
    settings = settings(profile)

    base =
      for size <- settings.sizes,
          payload <- settings.payloads,
          workload <- Fixtures.workloads(size, payload) do
        Map.merge(workload, %{
          id: "#{workload.name}/#{payload}/#{size}",
          dimensions: %{size: size, payload: payload}
        })
      end

    base ++ Enum.flat_map(settings.sizes, &extra_workloads/1)
  end

  def extra_workloads(size) when size in 2..32 do
    (Jido.Test.Perf.Signal.SignalCases.workloads(size) ++
       Jido.Test.Perf.Signal.RouterCases.workloads(size) ++
       Jido.Test.Perf.Signal.BusCases.workloads(size) ++
       Jido.Test.Perf.Signal.SelectorCases.workloads(size))
    |> Enum.map(&Map.put(&1, :id, "#{&1.name}/extended/#{size}"))
  end

  def extra_workloads(_), do: raise(ArgumentError, "extended size must be in 2..32")

  def check_growth! do
    for {name, fixture} <- [
          {"wildcard_router",
           fn size ->
             Jido.Test.Perf.Signal.RouterCases.wildcard_specs(size * 16) |> Jido.Signal.Router.new!()
           end},
          {"event_batch", &Jido.Test.Perf.Signal.Helpers.events/1}
        ] do
      [small, large] = for size <- [2, 32], do: Measure.term_size(fixture.(size))

      for measurement <- [small, large] do
        if measurement.copied_flat_heap_bytes != measurement.flat_heap_bytes,
          do: raise("#{name} copied heap differs from the flat heap")
      end

      ratio = large.flat_heap_bytes / small.flat_heap_bytes

      %{
        fixture: name,
        small_size: 2,
        large_size: 32,
        small_flat_bytes: small.flat_heap_bytes,
        large_flat_bytes: large.flat_heap_bytes,
        ratio: ratio
      }
    end
  end

  defp measure!(workload, operation) do
    operation.()
  rescue
    error -> reraise "#{workload.id}: #{Exception.message(error)}", __STACKTRACE__
  end

  def write!(report, directory) do
    File.mkdir_p!(directory)
    File.write!(Path.join(directory, "report.json"), Jason.encode!(report))
    File.write!(Path.join(directory, "report.md"), Report.markdown(report))
  end

  defp settings("candidates"),
    do: %{
      profile: "candidates",
      sizes: [2, 32],
      payloads: [],
      warmup: 3,
      samples: 15,
      resource_samples: 1
    }

  defp settings("short"),
    do: %{
      profile: "short",
      sizes: [8],
      payloads: [:small, :large_map, :large_binary],
      warmup: 3,
      samples: 15,
      resource_samples: 1
    }

  defp settings("scale"),
    do: %{
      profile: "scale",
      sizes: [2, 8, 32],
      payloads: [:small, :large_map, :large_binary],
      warmup: 5,
      samples: 30,
      resource_samples: 1
    }

  defp settings("smoke"),
    do: %{
      profile: "smoke",
      sizes: [2, 6],
      payloads: [:small],
      warmup: 1,
      samples: 2,
      resource_samples: 1
    }

  defp settings(_), do: raise(ArgumentError, "profile must be short, scale, smoke, or candidates")

  defp source do
    files = Path.wildcard(Path.expand("../**/*.exs", __DIR__)) |> Enum.sort()
    tool_sha = files |> Enum.map(&File.read!/1) |> hash()

    %{
      commit: command("git", ["rev-parse", "HEAD"]),
      runtime_dirty:
        command("git", ["status", "--porcelain", "--", "lib", "config", "mix.exs", "mix.lock"]) !=
          "",
      checkout_dirty: command("git", ["status", "--porcelain"]) != "",
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
      application_config_sha256:
        :jido
        |> Application.get_all_env()
        |> Enum.sort()
        |> :erlang.term_to_binary()
        |> hash(),
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
