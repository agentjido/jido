defmodule Jido.Test.Perf.Signal.Report do
  @moduledoc false

  def limitations do
    [
      "Timing runs without tracing or memory sampling. Setup, result checks, delivery drains, and cleanup are outside each timed interval.",
      "Timing reductions cover only the caller. Separate activity probes report caller and Bus reductions, net minor-GC count (can reset on full GC), and memory after forced GC. Other helper reductions and exact peaks remain unavailable (null).",
      "Observed memory maxima use start, setup, result, and completion barriers. Short allocations can be missed. Resource samples include setup and result checks.",
      "Process memory and heap include the caller and its traced descendants. Shared binary bytes count each observed off-heap reference once. ETS and application-owned Registry memory are excluded.",
      "VM memory includes the observer, loaded code, and unrelated activity. It does not establish ownership or leaks.",
      "Helper starts follow spawn traces from the measured caller. Existing application processes and the observer are excluded.",
      "Cleanup uses trace-delivery barriers and process monitors. Failed resource probes stop observed descendants before returning the failure.",
      "Flat and copied heap sizes exclude off-heap binary payloads. External bytes measure Erlang term encoding, not process-copy cost. Receiver memory includes process overhead.",
      "Retained terms are fixture inputs: attributes, Signals, encoded data, Routers, or event batches. They are not the full live Bus state.",
      "Async PID dispatch measures send completion. Original bus/fanout uses one mailbox. Extended fanout and concurrent publication wait for independent consumers. Checkpoint Signals confirm complete delivery after timing.",
      "Each Bus sample starts with controlled state. Sustained publication uses 64 batches on one full log. Backlog cases hold or release a consumer with explicit messages; no sleep controls consumer speed.",
      "Replay setup fills the log outside timing. Reconnect setup stops the old consumer before timing. Reconnect timing includes attachment, receipt, acknowledgement, and one-record delivery guards. Timeout timing includes the configured 2 ms wait.",
      "Mailbox counts sum queued messages at observation barriers. They are not an exact maximum. Slow-consumer publication deliberately retains its queue until the result check.",
      "Network adapters, external storage, VM restart recovery, and a complete failure matrix remain outside this suite. Telemetry has no benchmark handlers.",
      "Ratios are descriptive only and do not establish a speed improvement. This suite has no timing or memory pass threshold."
    ]
  end

  def markdown(report) do
    rows =
      Enum.map(report.cases, fn row ->
        "| #{row.id} | #{row.timing.wall_ns.median} | #{row.timing.wall_ns.p95} | #{row.timing.caller_reductions.median} | #{row.resources.observed_peak.process_memory_bytes} | #{row.resources.observed_peak.mailbox_messages} | #{row.resources.owned_process_starts} | #{row.resources.owned_remaining} |"
      end)

    """
    # Signal benchmark

    Commit: `#{report.source.commit}`. Runtime source dirty: `#{report.source.runtime_dirty}`.
    Tool SHA-256: `#{report.source.tool_sha256}`.
    Profile: `#{report.settings.profile}`. Elixir: `#{report.environment.elixir}`. OTP: `#{report.environment.otp}`.
    Warm-up: #{report.settings.warmup}. Timing samples per case: #{report.settings.samples}.
    See the JSON report for case dimensions, raw samples, term sizes, growth checks, memory details, and machine data.

    | Case | Median ns | p95 ns | Caller reductions | Observed process bytes | Queued messages | Helper starts | Remaining |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{Enum.join(rows, "\n")}

    ## Measurement limits

    #{Enum.map_join(limitations(), "\n", &("- " <> &1))}
    """
  end

  def compare!(before, after_report) do
    for field <- ["schema_version", "suite", "environment", "settings", "method"] do
      if Map.fetch!(before, field) != Map.fetch!(after_report, field),
        do: raise(ArgumentError, "reports have different #{field} values")
    end

    tool_hash = get_in(before, ["source", "tool_sha256"])

    if not is_binary(tool_hash) or tool_hash != get_in(after_report, ["source", "tool_sha256"]),
      do: raise(ArgumentError, "reports have missing or different tool hashes")

    old = index!(before)
    new = index!(after_report)

    if Enum.sort(Map.keys(old)) != Enum.sort(Map.keys(new)),
      do: raise(ArgumentError, "reports have different case sets")

    rows = for id <- Enum.sort(Map.keys(old)), do: comparison_row(id, old[id], new[id])

    """
    # Signal benchmark comparison

    Before: `#{get_in(before, ["source", "commit"])}`.
    After: `#{get_in(after_report, ["source", "commit"])}`.
    Each ratio is after / before. Values below 1 indicate a decrease.
    Environment, settings, method, and tool hash match. Check source state in both JSON files.

    | Case | Before median ns | After median ns | Time ratio | Caller reduction ratio | Observed process byte ratio | Flat input heap ratio | After remaining |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
    #{Enum.join(rows, "\n")}

    ## Measurement limits

    #{Enum.map_join(limitations(), "\n", &("- " <> &1))}
    """
  end

  defp comparison_row(id, before, candidate) do
    median_before = get_in(before, ["timing", "wall_ns", "median"])
    median_after = get_in(candidate, ["timing", "wall_ns", "median"])

    ratios =
      for path <- [
            ["timing", "wall_ns", "median"],
            ["timing", "caller_reductions", "median"],
            ["resources", "observed_peak", "process_memory_bytes"],
            ["retained_term", "flat_heap_bytes"]
          ] do
        ratio(get_in(before, path), get_in(candidate, path))
      end

    "| #{id} | #{median_before} | #{median_after} | #{Enum.join(ratios, " | ")} | #{candidate["resources"]["owned_remaining"]} |"
  end

  defp ratio(before, _candidate) when before == 0, do: "unavailable"
  defp ratio(before, candidate), do: :erlang.float_to_binary(candidate / before, decimals: 3)

  defp index!(report) do
    rows = Map.fetch!(report, "cases")
    indexed = Map.new(rows, &{Map.fetch!(&1, "id"), &1})
    if map_size(indexed) != length(rows), do: raise(ArgumentError, "duplicate case IDs")
    indexed
  end
end
