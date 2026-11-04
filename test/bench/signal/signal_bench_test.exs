Code.require_file("support/suite.exs", __DIR__)

defmodule JidoTest.Bench.Signal.SignalBenchTest do
  use ExUnit.Case, async: false
  @moduletag :bench

  alias Jido.Bench.Signal.{Fixtures, Measure, Report, Suite}

  test "all workloads check results and stop their processes for each payload" do
    for payload <- [:small, :large_map, :large_binary],
        workload <- Fixtures.workloads(2, payload) do
      timing = Measure.timing(workload, 1, 2)
      assert length(timing.wall_ns.samples) == 2
      assert timing.caller_reductions.min >= 0
      resources = Measure.resources(workload)
      assert resources.owned_remaining == 0
      assert resources.observations >= 3
      assert resources.observed_peak.process_memory_bytes > 0

      if String.starts_with?(workload.name, "bus/") do
        assert resources.owned_process_starts > 0
      end
    end
  end

  test "result checks reject a failed operation and still run cleanup" do
    owner = self()
    tag = make_ref()

    workload = %{
      setup: fn _ -> :prepared end,
      run: fn :prepared -> :wrong end,
      check: fn :right, :prepared -> :ok end,
      cleanup: fn :prepared -> send(owner, tag) end
    }

    assert_raise FunctionClauseError, fn -> Measure.timing(workload, 1, 1) end
    assert_receive ^tag
    assert_raise RuntimeError, ~r/resource caller failed/, fn -> Measure.resources(workload) end
    assert_receive ^tag
  end

  test "a failed resource probe stops unlinked children and grandchildren" do
    owner = self()
    tag = make_ref()

    workload = %{
      setup: fn _ -> nil end,
      run: fn _ ->
        caller = self()

        child =
          spawn(fn ->
            child = self()

            grandchild =
              spawn(fn ->
                send(child, {tag, :ready, self()})
                receive do: (:release -> :ok)
              end)

            receive do
              {^tag, :ready, ^grandchild} -> send(caller, {tag, child, grandchild})
            end

            receive do: (:release -> :ok)
          end)

        receive do
          {^tag, ^child, grandchild} -> send(owner, {tag, child, grandchild})
        end

        :wrong
      end,
      check: fn _, _ -> raise "probe rejected" end
    }

    assert_raise RuntimeError, ~r/resource caller failed:.*probe rejected/, fn ->
      Measure.resources(workload)
    end

    assert_received {^tag, child, grandchild}
    refute Process.alive?(child)
    refute Process.alive?(grandchild)
  end

  test "term transfer measures the copied heap and bounds flattened sharing" do
    term = Fixtures.signal(:large_binary)
    sizes = Measure.term_size(term)
    assert sizes.copied_flat_heap_bytes == sizes.flat_heap_bytes
    assert sizes.external_bytes > 1_048_576
    assert sizes.flat_heap_bytes < sizes.external_bytes

    shared = Enum.reduce(1..22, :leaf, fn _, child -> {child, child} end)

    assert_raise RuntimeError, ~r/64 MiB heap bound/, fn ->
      Measure.term_size(shared)
    end
  end

  test "statistics and input bounds are explicit" do
    assert %{median: 2.5, p95: 4, mean: 2.5, samples: [4, 1, 3, 2]} =
             Measure.distribution([4, 1, 3, 2])

    assert_raise ArgumentError, fn -> Fixtures.workloads(0, :small) end
    assert_raise ArgumentError, fn -> Fixtures.workloads(33, :small) end
    assert_raise ArgumentError, fn -> Suite.run("unknown") end
    assert_raise ArgumentError, fn -> Measure.timing(%{}, 0, 1) end
    assert_raise ArgumentError, fn -> Measure.timing(%{}, 1, 0) end
  end

  test "a smoke report can be written, read, and compared" do
    directory = Path.join(System.tmp_dir!(), "signal-bench-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(directory) end)
    report = Suite.run("smoke")
    Suite.write!(report, directory)

    assert report.suite == "jido.signal"
    assert length(report.cases) == 150
    assert report.schema_version == 2
    assert length(report.growth_checks) == 2
    assert Enum.all?(report.cases, &is_map(&1.dimensions))
    assert Enum.all?(report.cases, &(&1.resources.owned_remaining == 0))
    decoded = directory |> Path.join("report.json") |> File.read!() |> Jason.decode!()
    assert Report.compare!(decoded, decoded) =~ "1.000"
    assert File.read!(Path.join(directory, "report.md")) =~ "Signal benchmark"
  end

  test "comparison rejects incompatible reports and duplicate or missing cases" do
    before = comparison_fixture()
    candidate = put_in(before, ["cases", Access.at(0), "timing", "wall_ns", "median"], 120)
    assert Report.compare!(before, candidate) =~ "1.200"

    for field <- ["schema_version", "suite", "environment", "settings", "method"] do
      assert_raise ArgumentError, ~r/#{field}/, fn ->
        Report.compare!(before, Map.put(candidate, field, "changed"))
      end
    end

    assert_raise ArgumentError, ~r/tool/, fn ->
      Report.compare!(before, put_in(candidate, ["source", "tool_sha256"], "changed"))
    end

    assert_raise ArgumentError, ~r/case/, fn ->
      Report.compare!(before, %{candidate | "cases" => []})
    end

    assert_raise ArgumentError, ~r/duplicate/, fn ->
      Report.compare!(before, %{candidate | "cases" => candidate["cases"] ++ candidate["cases"]})
    end

    reordered = %{candidate | "cases" => Enum.reverse(candidate["cases"])}
    assert Report.compare!(before, reordered) == Report.compare!(before, candidate)
  end

  test "comparison handles a zero median from an even sample count" do
    before =
      put_in(comparison_fixture(), ["cases", Access.at(0), "timing", "wall_ns", "median"], 0.0)

    assert Report.compare!(before, comparison_fixture()) =~ "unavailable"
  end

  defp comparison_fixture do
    row = %{
      "id" => "signal/new/small/2",
      "timing" => %{"wall_ns" => %{"median" => 100}, "caller_reductions" => %{"median" => 10}},
      "resources" => %{
        "owned_process_starts" => 0,
        "owned_remaining" => 0,
        "observed_peak" => %{"process_memory_bytes" => 1_000}
      },
      "retained_term" => %{"flat_heap_bytes" => 100}
    }

    %{
      "schema_version" => 1,
      "suite" => "jido.signal",
      "source" => %{"tool_sha256" => "same-tool"},
      "method" => "test-method",
      "environment" => %{"otp" => "27"},
      "settings" => %{"samples" => 2},
      "cases" => [row, %{row | "id" => "signal/to_map/small/2"}]
    }
  end
end
