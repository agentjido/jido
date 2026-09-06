Code.require_file("../../../bench/support/suite.exs", __DIR__)

defmodule JidoCoreBenchTest do
  use ExUnit.Case, async: false
  alias JidoCoreBench.{Fixtures, Measure, Report, Suite}

  setup do
    start_supervised!({Jido, name: JidoCoreBench})
    :ok
  end

  test "smoke cases check results, copied values, and process cleanup" do
    workloads = Suite.workloads("smoke")
    assert length(workloads) == 115
    assert length(Enum.uniq_by(workloads, & &1.id)) == length(workloads)

    for w <- workloads do
      assert length(Measure.timing(w, 1, 2).wall_ns.samples) == 2
      resources = Measure.resources(w)
      assert resources.median.owned_remaining == 0
      assert resources.median.observations > 0

      for {_name, term} <- Measure.retained(w) do
        assert term.copied_flat_heap_bytes == term.flat_heap_bytes
      end

      assert Task.Supervisor.children(JidoCoreBench.TaskSupervisor) == []
    end
  end

  test "resource samples use separate callers and keep raw measurements" do
    owner = self()
    tag = make_ref()

    w =
      Fixtures.checked(
        "caller",
        fn _ -> nil end,
        fn _ ->
          send(owner, {tag, self()})
          :ok
        end,
        &Fixtures.equal!(&1, :ok)
      )

    resources = Measure.resources(w, 3)

    callers =
      for _ <- 1..3 do
        assert_received {^tag, pid}
        refute Process.alive?(pid)
        pid
      end

    assert length(Enum.uniq(callers)) == 3
    assert length(resources.samples) == 3
    peaks = Enum.map(resources.samples, & &1.observed_peak.process_memory_bytes)
    assert resources.median.observed_peak.process_memory_bytes == Enum.at(Enum.sort(peaks), 1)
  end

  test "incorrect results fail and teardown runs in all measurement modes" do
    owner = self()

    w =
      Fixtures.checked("wrong", fn _ -> nil end, fn _ -> :wrong end, fn _ ->
        raise "wrong result"
      end)
      |> Map.put(:cleanup, fn _ -> send(owner, :cleaned) end)

    assert_raise RuntimeError, "wrong result", fn -> Measure.timing(w, 1, 1) end
    assert_received :cleaned
    assert_raise RuntimeError, "wrong result", fn -> Measure.retained(w) end
    assert_received :cleaned
    assert_raise RuntimeError, ~r/resource caller failed/, fn -> Measure.resources(w) end
    assert_received :cleaned
  end

  test "a failed resource call removes its owned child and grandchild" do
    owner = self()
    tag = make_ref()

    w =
      Fixtures.checked(
        "leak",
        fn _ -> nil end,
        fn _ ->
          caller = self()

          {:ok, child} =
            Task.Supervisor.start_child(JidoCoreBench.TaskSupervisor, fn ->
              Process.flag(:trap_exit, true)
              child = self()

              grandchild =
                spawn(fn ->
                  Process.flag(:trap_exit, true)
                  send(owner, {tag, child, self()})
                  send(caller, {tag, :ready})
                  receive do: (:release -> :ok)
                end)

              receive do: (:release -> Process.exit(grandchild, :kill))
            end)

          receive do
            {^tag, :ready} -> child
          after
            5_000 -> raise "child did not start"
          end
        end,
        fn _ -> raise "failed probe" end
      )

    assert_raise RuntimeError, ~r/failed probe/, fn -> Measure.resources(w) end
    assert_received {^tag, child, grandchild}
    refute Process.alive?(child)
    refute Process.alive?(grandchild)
    assert Task.Supervisor.children(JidoCoreBench.TaskSupervisor) == []
  end

  test "shared terms cannot bypass the flat heap transfer limit" do
    term = Enum.reduce(1..22, :leaf, fn _, child -> {child, child} end)
    assert :erts_debug.size(term) < 1_000
    assert_raise RuntimeError, ~r/64 MiB/, fn -> Measure.term_size(term) end
  end

  test "an untraced helper cannot pass suite completion while it is still running" do
    {:ok, pid} =
      Task.Supervisor.start_child(JidoCoreBench.TaskSupervisor, fn ->
        receive do: (:release -> :ok)
      end)

    try do
      assert_raise RuntimeError, ~r/benchmark helper did not stop/, fn ->
        Suite.ensure_idle!(0)
      end
    after
      Task.Supervisor.terminate_child(JidoCoreBench.TaskSupervisor, pid)
    end

    assert :ok == Suite.ensure_idle!()
  end

  test "comparison rejects changes in conditions and duplicate cases" do
    row = %{
      "id" => "probe",
      "timing" => %{"wall_ns" => %{"median" => 100}},
      "resources" => %{
        "median" => %{
          "owned_process_starts" => 0,
          "owned_remaining" => 0,
          "observed_peak" => %{"process_memory_bytes" => 100, "shared_binary_bytes" => 0}
        }
      }
    }

    report = %{
      "schema_version" => 1,
      "source" => %{"tool_sha256" => "same"},
      "environment" => %{"otp" => "29"},
      "settings" => %{"samples" => 2},
      "method" => "test",
      "cases" => [row]
    }

    assert Report.compare!(report, report) =~ "1.000"

    for key <- ["schema_version", "environment", "settings", "method"] do
      assert_raise ArgumentError, fn ->
        Report.compare!(report, Map.put(report, key, "changed"))
      end
    end

    assert_raise ArgumentError, ~r/tool/, fn ->
      Report.compare!(report, put_in(report, ["source", "tool_sha256"], "changed"))
    end

    assert_raise ArgumentError, ~r/duplicate/, fn ->
      Report.compare!(report, %{report | "cases" => [row, row]})
    end

    assert_raise ArgumentError, ~r/case/, fn ->
      Report.compare!(report, %{report | "cases" => []})
    end
  end
end
