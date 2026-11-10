Code.require_file("../support/fuzz.exs", __DIR__)
Code.require_file("../support/jido_signal/runtime.exs", __DIR__)
Code.require_file("../support/report.exs", __DIR__)

defmodule Jido.Signal.Property.FuzzSupportTest do
  use ExUnit.Case, async: true
  @moduletag :property
  alias Jido.Test.Property.{Fuzz, Report}
  alias Jido.Test.Property.Signal.Runtime

  setup do
    root =
      Path.join([
        Mix.Project.build_path(),
        "fuzz-support-tests",
        "#{System.pid()}-#{System.unique_integer([:positive])}"
      ])

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "counts samples and observations but does not count shrink trials as evidence", %{
    root: root
  } do
    opts = [root: root, seed: 0, max_runs: 10, examples: [0]]

    assert_raise ExUnit.AssertionError, fn ->
      Fuzz.check("fault_probe", StreamData.integer(0..100), opts, fn value ->
        assert value < 3
        ["below-three"]
      end)
    end

    stats = stats(root, "fault_probe")
    assert stats["outcome"] == "failed"
    assert stats["reproduced"]
    assert stats["examples"] == 1
    assert stats["confirmations"] == 1
    assert stats["shrink_attempts"] == stats["shrink_nodes_visited"]
    assert stats["observations"]["below-three"] == stats["generated"]
    saved = stats["counterexample"] |> File.read!() |> JSON.decode!()
    assert saved["input"] == 3

    # The same failure is checked before any new random sample in the next run.
    assert_raise ExUnit.AssertionError, fn ->
      Fuzz.check("fault_probe", StreamData.constant(0), opts, fn value ->
        assert value < 3
        ["below-three"]
      end)
    end

    replay = stats(root, "fault_probe")
    assert replay["failed_phase"] == "replayed"
    assert replay["generated"] == 0
    assert replay["replayed"] == 1

    # Fixing the assertion keeps the saved case as regression input.
    Fuzz.check("fault_probe", StreamData.constant(0), opts, fn _ -> ["accepted"] end)
    assert stats(root, "fault_probe")["replayed"] == 1
    assert File.exists?(stats["counterexample"])
  end

  test "cleanup runs on every generated, shrunk, and confirmed attempt", %{root: root} do
    token = make_ref()

    assert_raise RuntimeError, "probe", fn ->
      Fuzz.check(
        "cleanup_probe",
        StreamData.integer(1..10),
        [root: root, seed: 1, max_runs: 1],
        fn value ->
          Runtime.with_bus(fn %{bus: bus} ->
            send(self(), {token, [bus], value})
            raise "probe"
          end)
        end
      )
    end

    counts = stats(root, "cleanup_probe")

    for _ <- 1..(counts["generated"] + counts["shrink_attempts"] + counts["confirmations"]) do
      assert_received {^token, workers, _value}
      Runtime.assert_workers_stopped(workers)
    end

    refute_received {^token, _}
  end

  test "a failure that does not replay remains a failure", %{root: root} do
    key = make_ref()
    Process.put(key, true)

    try do
      assert_raise RuntimeError, "one-time failure", fn ->
        Fuzz.check(
          "unstable_probe",
          StreamData.constant(0),
          [root: root, seed: 1, max_runs: 1],
          fn _ ->
            if Process.delete(key), do: raise("one-time failure")
            []
          end
        )
      end

      assert stats(root, "unstable_probe")["reproduced"] == false
      assert stats(root, "unstable_probe")["outcome"] == "failed"
    after
      Process.delete(key)
    end
  end

  test "property and fuzz variants retain separate measurements", %{root: root} do
    for {variant, runs} <- [property: 2, fuzz: 3] do
      Fuzz.check(
        "variants",
        StreamData.constant(0),
        [root: root, fuzz: variant == :fuzz, max_runs: runs],
        fn _ -> [] end
      )
    end

    assert stats(root, "variants", :property)["generated"] == 2
    assert stats(root, "variants", :fuzz)["generated"] == 3
  end

  test "measurements retain their family and test timeout", %{root: root} do
    Fuzz.check(
      "measurement_metadata",
      StreamData.constant(0),
      [
        root: root,
        fuzz: true,
        max_runs: 1,
        timeout: 900_000
      ],
      fn _ -> ["one-call"] end
    )

    record = stats(root, "measurement_metadata", :fuzz)
    assert record["family"] == "test"
    assert record["test_timeout"] == 900_000
  end

  test "saved failures retain the owning family", %{root: root} do
    assert_raise RuntimeError, "contract probe", fn ->
      Fuzz.check(
        "contract_failure",
        StreamData.constant(0),
        [root: root, max_runs: 1],
        fn _ -> raise "contract probe" end
      )
    end

    saved = stats(root, "contract_failure")["counterexample"] |> File.read!() |> JSON.decode!()
    assert saved["family"] == "test"
  end

  test "saved failure contains the current incomplete report source", %{root: root} do
    {:ok, state} = Report.init(path: Path.join(root, "property-report.json"))

    assert_raise RuntimeError, "metadata probe", fn ->
      Fuzz.check("source_failure", StreamData.constant(0), [root: root, max_runs: 1], fn _ ->
        raise "metadata probe"
      end)
    end

    [path] =
      Path.wildcard(Path.join([root, "property-counterexamples", "test", "source_failure", "*.json"]))

    saved = path |> File.read!() |> JSON.decode!()

    expected =
      state.metadata
      |> Map.take([:revision, :working_tree_dirty, :source_digest, :run_id])
      |> JSON.encode!()
      |> JSON.decode!()

    assert saved["source"] == expected
  end

  test "bad replay data fails before generation and leaves a failed report", %{root: root} do
    path = Path.join(root, "broken.json")
    File.mkdir_p!(root)
    File.write!(path, "not json")

    assert_raise ArgumentError, ~r/invalid fuzz replay file/, fn ->
      Fuzz.check("bad_replay", StreamData.constant(0), [root: root, corpus: [path]], fn _ ->
        flunk("generation must not start")
      end)
    end

    assert stats(root, "bad_replay")["outcome"] == "failed"
    assert stats(root, "bad_replay")["failed_phase"] == "replay_load"
    assert stats(root, "bad_replay")["generated"] == 0
  end

  test "invalid budgets cannot produce a passing zero-sample run", %{root: root} do
    for option <- [
          [max_runs: 0],
          [max_runs: -1],
          [max_run_time: 0],
          [max_runs: "10"],
          [max_shrinking_steps: -1]
        ] do
      assert_raise ArgumentError, ~r/invalid fuzz budget/, fn ->
        Fuzz.check("invalid_budget", StreamData.constant(0), [root: root] ++ option, fn _ ->
          flunk("invalid budgets must fail before work")
        end)
      end
    end
  end

  test "the property macro cannot silently make a fuzz case part of both suites", %{root: root} do
    assert_raise ArgumentError, ~r/property and fuzz tags must not overlap/, fn ->
      Fuzz.check(
        "overlapping_tags",
        StreamData.constant(0),
        [root: root, property: true, fuzz: true],
        fn _ -> [] end
      )
    end
  end

  test "variants can save the same failure without partial records or temporary files", %{
    root: root
  } do
    owner = self()
    token = make_ref()

    tasks =
      for variant <- [:property, :fuzz] do
        Task.async(fn ->
          assert_raise RuntimeError, "shared failure", fn ->
            Fuzz.check(
              "shared_failure",
              StreamData.constant(0),
              [root: root, fuzz: variant == :fuzz],
              fn _ ->
                send(owner, {token, :ready, self()})

                receive do
                  ^token -> raise "shared failure"
                end
              end
            )
          end
        end)
      end

    try do
      # Both variants finish reading the empty corpus before either writes it.
      # A constant generator then has one repeat check and no shrink candidates.
      for _ <- 1..2 do
        workers =
          for _ <- tasks do
            assert_receive {^token, :ready, worker}, 5_000
            worker
          end

        Enum.each(workers, &send(&1, token))
      end

      Enum.each(tasks, &Task.await/1)
    after
      for task <- tasks, Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    end

    first = stats(root, "shared_failure", :property)
    second = stats(root, "shared_failure", :fuzz)
    assert first["counterexample"] == second["counterexample"]
    assert first["reproduced"] and second["reproduced"]

    assert %{"input" => 0, "property" => "shared_failure"} =
             first["counterexample"] |> File.read!() |> JSON.decode!()

    assert Path.wildcard(Path.join(root, "**/*.tmp")) == []
  end

  defp stats(root, id, variant \\ :property),
    do:
      Path.join([root, "property-fuzz", "standalone", "test", "#{id}-#{variant}.json"])
      |> File.read!()
      |> JSON.decode!()
end
