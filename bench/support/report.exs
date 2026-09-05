defmodule JidoCoreBench.Report do
  @moduledoc false

  def limitations do
    [
      "Time covers the operation only. Setup, result checks, teardown, tracing, and memory probes are outside the timed interval.",
      "Resource runs include setup, operation, checks, and teardown. Reported memory is the largest observed barrier sample, not the exact lifetime peak.",
      "Caller reductions exclude helper work. Observed helper reductions and traced GC counts come from separate resource calls. Exact total reductions and peak memory are unavailable (null).",
      "Process memory sums the caller and observed descendants. Binary bytes deduplicate observed references; binary ownership can be shared. VM memory includes unrelated work and the observer.",
      "A dedicated Task.Supervisor and the caller are trace roots. Spawn traces identify descendants. Explicit teardown and monitors confirm cleanup; global process counts do not establish leaks.",
      "Term probes transfer checked values to a new process. Flat heap excludes off-heap binary bytes. The 64 MiB flat heap bound prevents unsafe transfers of deeply shared terms.",
      "Retained terms come from a separate checked operation. They include Agent definitions, schemas, routes, and returned data. Server results do not represent all server internal state.",
      "Server setup is outside timing. Resource runs include server startup. Burst timing covers 20 casts and a final synchronous call from the same sender. Per-call tail latency under concurrent load is not measured.",
      "Samples use bounded local fixtures without network work. Distributed callers, durable scheduler recovery, topology activation, and provider latency need later fixtures.",
      "Ratios are candidate / baseline. No speedup claim follows from one shared-host run. Repeat with identical scripts, dependencies, runtime, settings, and idle host."
    ]
  end

  def markdown(report) do
    rows =
      Enum.map(report.cases, fn row ->
        resources = row.resources.median

        "| #{row.id} | #{row.timing.wall_ns.median} | #{row.timing.wall_ns.p95} | #{resources.observed_peak.process_memory_bytes} | #{resources.observed_peak.shared_binary_bytes} | #{resources.owned_process_starts} | #{resources.owned_remaining} |"
      end)

    retained_rows =
      for row <- report.cases, {name, term} <- Enum.sort(row.retained_terms) do
        "| #{row.id} | #{name} | #{term.local_heap_bytes} | #{term.copied_flat_heap_bytes} | #{term.external_bytes} |"
      end

    """
    # Jido core benchmark

    Commit: `#{report.source.commit}`. Runtime source dirty: `#{report.source.runtime_dirty}`.
    Tool SHA-256: `#{report.source.tool_sha256}`.
    Profile: `#{report.settings.profile}`. Elixir: `#{report.environment.elixir}`. OTP: `#{report.environment.otp}`.
    Warm-up: #{report.settings.warmup}. Timing samples per case: #{report.settings.samples}.
    Resource samples per case: #{report.settings.resource_samples}. Memory and helper columns show field medians.
    See the JSON report for raw samples, reductions, term sizes, memory, and full machine data.

    | Case | Median ns | p95 ns | Process bytes | Binary bytes | Helper starts | Remaining |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: |
    #{Enum.join(rows, "\n")}

    ## Retained terms

    | Case | Term | Local heap bytes | Copied heap bytes | External bytes |
    | --- | --- | ---: | ---: | ---: |
    #{Enum.join(retained_rows, "\n")}

    ## Measurement limits

    #{Enum.map_join(limitations(), "\n", &("- " <> &1))}
    """
  end

  def compare!(before, after_report) do
    for field <- ["schema_version", "environment", "settings", "method"] do
      if Map.fetch!(before, field) != Map.fetch!(after_report, field) do
        raise ArgumentError, "reports have different #{field} values"
      end
    end

    tool_hash = get_in(before, ["source", "tool_sha256"])

    if not is_binary(tool_hash) or tool_hash != get_in(after_report, ["source", "tool_sha256"]),
      do: raise(ArgumentError, "reports have missing or different tool hashes")

    old = index!(before)
    new = index!(after_report)

    if Enum.sort(Map.keys(old)) != Enum.sort(Map.keys(new)),
      do: raise(ArgumentError, "reports have different case sets")

    rows =
      for id <- Enum.sort(Map.keys(old)) do
        a = old[id]
        b = new[id]
        median_a = a["timing"]["wall_ns"]["median"]
        median_b = b["timing"]["wall_ns"]["median"]

        resources_a = a["resources"]["median"]
        resources_b = b["resources"]["median"]

        process_ratio =
          ratio(
            resources_a["observed_peak"]["process_memory_bytes"],
            resources_b["observed_peak"]["process_memory_bytes"]
          )

        binary_ratio =
          ratio(
            resources_a["observed_peak"]["shared_binary_bytes"],
            resources_b["observed_peak"]["shared_binary_bytes"]
          )

        "| #{id} | #{median_a} | #{median_b} | #{ratio(median_a, median_b)} | #{process_ratio} | #{binary_ratio} | #{resources_a["owned_process_starts"]} → #{resources_b["owned_process_starts"]} | #{resources_b["owned_remaining"]} |"
      end

    """
    # Jido core benchmark comparison

    Before: `#{get_in(before, ["source", "commit"])}`.
    After: `#{get_in(after_report, ["source", "commit"])}`.
    Ratio is after / before. No speedup claim is made. Environment, settings, method, and tool hash match.
    Check runtime source state in both JSON files before using these ratios.

    | Case | Before median ns | After median ns | Time ratio | Process bytes ratio | Binary bytes ratio | Helper starts | After remaining |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{Enum.join(rows, "\n")}

    ## Measurement limits

    #{Enum.map_join(limitations(), "\n", &("- " <> &1))}
    """
  end

  defp ratio(0, _after), do: "unavailable"
  defp ratio(before, after_value), do: :erlang.float_to_binary(after_value / before, decimals: 3)

  defp index!(report) do
    rows = Map.fetch!(report, "cases")
    if rows == [], do: raise(ArgumentError, "empty case set")
    indexed = Map.new(rows, &{Map.fetch!(&1, "id"), &1})
    if map_size(indexed) != length(rows), do: raise(ArgumentError, "duplicate case IDs")
    indexed
  end
end
