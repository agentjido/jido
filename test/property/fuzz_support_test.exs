Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/authoring.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)

defmodule JidoTest.Property.FuzzSupportTest do
  use ExUnit.Case, async: true
  @moduletag :property
  alias JidoTest.Property.{Authoring, Fuzz, Report}

  setup do
    root =
      Path.join([
        Mix.Project.build_path(),
        "fuzz-support-tests",
        "#{System.pid()}-#{System.unique_integer([:positive])}"
      ])

    Report.prepare!(Path.join(root, "property-report.json"))
    File.write!(Path.join(root, "contracts.md"), "| CORE-001 | Probe | Cases |\n")
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

  test "compiled fixtures leave no current or old code after success or failure" do
    for fail? <- [false, true] do
      module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")
      source = "defmodule #{inspect(module)} do; def value, do: 1; end"

      callback = fn compiled ->
        assert module in compiled
        assert apply(module, :value, []) == 1
        # Load a second version to exercise old-code removal too.
        Code.with_diagnostics([log: false], fn ->
          Code.compile_string("defmodule #{inspect(module)} do; def value, do: 2; end")
        end)

        if fail?, do: raise("callback mutation")
        assert apply(module, :value, []) == 2
      end

      if fail? do
        assert_raise RuntimeError, "callback mutation", fn ->
          Authoring.with_compiled(source, callback, modules: [module])
        end
      else
        Authoring.with_compiled(source, callback, modules: [module])
      end

      assert :code.is_loaded(module) == false
      refute :erlang.check_old_code(module)
    end
  end

  test "attempt cleanup completes for generation, shrinking and confirmation", %{root: root} do
    token = make_ref()

    assert_raise RuntimeError, "attempt mutation", fn ->
      Fuzz.check("attempt_cleanup", StreamData.integer(1..10), [root: root, max_runs: 1], fn _ ->
        {pid, ref} =
          spawn_monitor(fn ->
            receive do
              :stop -> :ok
            end
          end)

        try do
          raise "attempt mutation"
        after
          send(pid, :stop)
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
          send(self(), {token, pid})
        end
      end)
    end

    record = stats(root, "attempt_cleanup")

    for _ <- 1..(record["generated"] + record["shrink_attempts"] + record["confirmations"]) do
      assert_received {^token, pid}
      refute Process.alive?(pid)
    end

    refute_received {^token, _}
  end

  test "after_verify failure removes partially compiled fixture modules" do
    module = Module.concat(__MODULE__, "Verify#{System.unique_integer([:positive])}")
    checker = Module.concat(module, Checker)

    source = """
    defmodule #{inspect(checker)} do
      def verify(_module), do: raise("verify mutation")
    end
    defmodule #{inspect(module)} do
      @after_verify {#{inspect(checker)}, :verify}
      def value, do: :ok
    end
    """

    assert_raise RuntimeError, "verify mutation", fn ->
      Authoring.with_compiled(source, fn _ -> flunk("verification must finish first") end,
        modules: [module]
      )
    end

    for compiled <- [module, checker] do
      assert :code.is_loaded(compiled) == false
      refute :erlang.check_old_code(compiled)
    end
  end

  test "inline Action modules outside the fixture namespace are also removed" do
    module = Module.concat(__MODULE__, "Inline#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "property_inline_cleanup"
      agent do
        schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      end
      routes do
        route "property.inline" do
          action %{}, schema: Zoi.object(%{}), context: context do
            {:ok, context.agent_state}
          end
        end
      end
    end
    """

    target =
      Authoring.with_compiled(
        source,
        fn _ -> apply(module, :route_action!, ["property.inline"]) end,
        modules: [module]
      )

    assert :code.is_loaded(module) == false
    assert :code.is_loaded(target) == false
    refute :erlang.check_old_code(module)
    refute :erlang.check_old_code(target)
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

  test "measurements retain public contract tags and the test timeout", %{root: root} do
    Fuzz.check(
      "contract_metadata",
      StreamData.constant(0),
      [
        root: root,
        fuzz: true,
        max_runs: 1,
        timeout: 900_000,
        contracts: ["BUS-001"],
        contract_cases: ["BUS-001/once"]
      ],
      fn _ -> ["one-call"] end
    )

    record = stats(root, "contract_metadata", :fuzz)
    assert record["contracts"] == ["BUS-001"]
    assert record["declared_forced_cases"] == ["BUS-001/once"]
    assert record["test_timeout"] == 900_000
  end

  test "saved failures retain the owning public contracts", %{root: root} do
    assert_raise RuntimeError, "contract probe", fn ->
      Fuzz.check(
        "contract_failure",
        StreamData.constant(0),
        [root: root, max_runs: 1, contracts: ["BUS-001"]],
        fn _ -> raise "contract probe" end
      )
    end

    saved = stats(root, "contract_failure")["counterexample"] |> File.read!() |> JSON.decode!()
    assert saved["contracts"] == ["BUS-001"]
  end

  test "saved failure contains the current incomplete report source", %{root: root} do
    {:ok, state} =
      Report.init(
        path: Path.join(root, "property-report.json"),
        register: Path.join(root, "contracts.md")
      )

    assert_raise RuntimeError, "metadata probe", fn ->
      Fuzz.check("source_failure", StreamData.constant(0), [root: root, max_runs: 1], fn _ ->
        raise "metadata probe"
      end)
    end

    [path] =
      Path.wildcard(Path.join([root, "property-counterexamples", "source_failure", "*.json"]))

    saved = path |> File.read!() |> JSON.decode!()

    expected =
      state.metadata
      |> Map.take([
        :revision,
        :working_tree_dirty,
        :source_digest,
        :dependencies,
        :runtime,
        :elixir,
        :otp,
        :otp_version,
        :zoi,
        :stream_data,
        :run_id
      ])
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

  test "incomplete measurements exist before assertion work starts", %{root: root} do
    Fuzz.check("early_evidence", StreamData.constant(0), [root: root, max_runs: 1], fn _ ->
      report = Path.join(root, "property-report.json") |> File.read!() |> JSON.decode!()
      assert report["status"] == "incomplete"
      assert is_binary(report["runtime"])
      assert is_map(report["dependencies"])
      assert stats(root, "early_evidence")["outcome"] == "incomplete"
      ["early-metadata"]
    end)
  end

  test "opaque generated resources reject before assertion work", %{root: root} do
    assert_raise ArgumentError, ~r/plain JSON data/, fn ->
      Fuzz.check("opaque_input", StreamData.constant(self()), [root: root, max_runs: 1], fn _ ->
        flunk("opaque input must not reach the model")
      end)
    end

    assert stats(root, "opaque_input")["outcome"] == "failed"
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

  defp stats(root, id, variant \\ :property) do
    [path] = Path.wildcard(Path.join([root, "property-fuzz", "*", "#{id}-#{variant}.json"]))
    path |> File.read!() |> JSON.decode!()
  end
end
