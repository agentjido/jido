Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)

defmodule JidoTest.Property.RuntimeContractTest do
  use JidoTest.Case, async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Flow
  alias Jido.Flow.{Ref, Step}
  alias JidoTest.AgentFixtures.{Add, BlockingAdd, Fail, InvalidState, WithDirective}
  alias JidoTest.Property.Fuzz

  @life_cases [
    "LIFE-001/cancel-blocked",
    "LIFE-001/completion-before-cancel",
    "LIFE-001/owner-death-action",
    "LIFE-001/owner-death-flow",
    "LIFE-001/serial-admission",
    "LIFE-001/actual-stale-handle"
  ]
  @turn_cases [
    "TURN-003/execution-failure",
    "TURN-003/invalid-state",
    "TURN-003/invalid-directive",
    "TURN-003/failure-then-success",
    "TURN-003/external-io-not-rolled-back"
  ]

  for suite <- [:property, :fuzz] do
    @tag suite
    @tag fuzz_id: "runtime_lifecycle"
    @tag contracts: ["LIFE-001"]
    @tag contract_cases: @life_cases
    @tag timeout: if(suite == :fuzz, do: 180_000, else: 30_000)
    test "#{suite} serial admission and execution resource ownership", %{jido: jido} do
      Fuzz.check(
        "runtime_lifecycle",
        life_generator(),
        budgets(unquote(suite)) ++
          [contracts: ["LIFE-001"], contract_cases: @life_cases, examples: life_examples()],
        fn input -> life_attempt(jido, input) end
      )
    end

    @tag suite
    @tag fuzz_id: "runtime_precommit"
    @tag contracts: ["TURN-003"]
    @tag contract_cases: @turn_cases
    @tag timeout: if(suite == :fuzz, do: 180_000, else: 30_000)
    test "#{suite} failed candidates preserve the committed model", %{jido: jido} do
      Fuzz.check(
        "runtime_precommit",
        turn_generator(),
        budgets(unquote(suite)) ++
          [contracts: ["TURN-003"], contract_cases: @turn_cases, examples: turn_examples()],
        fn input -> turn_attempt(jido, input) end
      )
    end
  end

  defp budgets(suite) do
    [
      fuzz: suite == :fuzz,
      max_runs: if(suite == :fuzz, do: 300, else: 30),
      max_run_time: if(suite == :fuzz, do: 120_000, else: 10_000),
      max_shrinking_steps: 100,
      timeout: if(suite == :fuzz, do: 180_000, else: 30_000)
    ]
  end

  defp life_generator do
    StreamData.fixed_map(%{
      "schedule" => StreamData.member_of(["cancel", "complete", "owner_death"]),
      "route" => StreamData.member_of(["action", "flow"]),
      "first" => StreamData.integer(-20..20),
      "second" => StreamData.integer(-20..20)
    })
  end

  defp life_examples do
    for schedule <- ["cancel", "complete", "owner_death"], route <- ["action", "flow"] do
      %{"schedule" => schedule, "route" => route, "first" => 2, "second" => -1}
    end
  end

  defp turn_generator do
    step =
      StreamData.fixed_map(%{
        "mode" =>
          StreamData.member_of(["success", "failure", "invalid_state", "invalid_directive"]),
        "by" => StreamData.integer(-20..20)
      })

    StreamData.fixed_map(%{"steps" => StreamData.list_of(step, min_length: 1, max_length: 12)})
  end

  defp turn_examples do
    [
      %{
        "steps" =>
          for(
            mode <- ["success", "failure", "invalid_state", "invalid_directive", "success"],
            do: %{"mode" => mode, "by" => 2}
          )
      }
    ]
  end

  defp counter do
    held_flow =
      Flow.new!(
        name: "property_held_counter",
        components: [
          Step.new!(
            name: "held",
            action: BlockingAdd,
            params: %{
              by: Ref.input(:by),
              label: Ref.input(:label),
              test_pid: Ref.input(:test_pid),
              gate: Ref.input(:gate)
            }
          )
        ],
        output: Ref.result("held")
      )

    Agent.new!(
      name: "property_counter",
      schema: Zoi.object(%{count: Zoi.integer(), history: Zoi.list(Zoi.string())}),
      routes: [
        {"counter.add", Add},
        {"counter.action", BlockingAdd},
        {"counter.flow", held_flow},
        {"counter.failure", Fail},
        {"counter.invalid_state", InvalidState},
        {"counter.invalid_directive", WithDirective}
      ]
    )
    |> Agent.instantiate!(id: unique_id("property-counter"), state: %{count: 0, history: []})
  end

  defp with_server(jido, callback) do
    key = {__MODULE__, make_ref()}
    Process.put(key, [])

    try do
      {:ok, server} =
        Jido.start_agent(jido, counter(),
          restart: :temporary,
          turn_timeout: 10_000,
          exec_opts: [timeout: :infinity]
        )

      remember(key, server)
      Process.put({key, :server}, server)
      callback.(server, key)
    after
      if server = Process.delete({key, :server}) do
        if Process.alive?(server) do
          try do
            Server.stop(server)
          catch
            :exit, _reason -> :ok
          end
        end
      end

      resources =
        (Process.delete(key) || []) ++
          Task.Supervisor.children(Jido.task_supervisor_name(jido))

      for pid <- Enum.uniq(resources) do
        ref = Process.monitor(pid)
        if Process.alive?(pid), do: Process.exit(pid, :kill)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
      end
    end
  end

  defp remember(key, pid), do: Process.put(key, [pid | Process.get(key)])

  defp runtime_signal(type, data), do: Jido.Signal.new!(type, data, source: "/property/runtime")

  defp start_call(server, input, key) do
    owner = self()
    tag = make_ref()

    {pid, ref} =
      spawn_monitor(fn ->
        result =
          try do
            Server.call(server, input, 20_000)
          catch
            :exit, reason -> {:caller_exit, reason}
          end

        send(owner, {tag, result})
      end)

    remember(key, pid)
    {pid, ref, tag}
  end

  defp call_result({pid, ref, tag}) do
    assert_receive {^tag, result}, 2_000
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    result
  end

  defp blocked(server, key, gate) do
    assert_receive {:agent_action_blocked, ^gate, worker}, 2_000
    remember(key, worker)
    {:running, data} = :sys.get_state(server)
    handle = data.active.exec_handle
    remember(key, handle.pid)
    {worker, data.active, Process.monitor(worker), Process.monitor(handle.pid)}
  end

  defp life_attempt(jido, input) do
    with_server(jido, fn server, key ->
      first_gate = make_ref()

      first =
        start_call(
          server,
          runtime_signal(
            "counter." <> input["route"],
            %{by: input["first"], label: "first", test_pid: self(), gate: first_gate}
          ),
          key
        )

      {worker, old, worker_ref, root_ref} = blocked(server, key, first_gate)
      assert Server.agent(server).state == %{count: 0, history: []}
      assert Server.status(server).state_version == 0

      if input["schedule"] == "owner_death" do
        server_ref = Process.monitor(server)
        Process.exit(server, :kill)
        assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 2_000
        root = old.exec_handle.pid
        assert_receive {:DOWN, ^root_ref, :process, ^root, _reason}, 2_000
        assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
        assert {:caller_exit, _reason} = call_result(first)
        ["LIFE-001/owner-death-" <> input["route"]]
      else
        second_gate = make_ref()

        :ok =
          Server.cast(
            server,
            runtime_signal(
              "counter.action",
              %{by: input["second"], label: "second", test_pid: self(), gate: second_gate}
            )
          )

        # The state query is a same-sender barrier after the queued cast.
        {:running, queued} = :sys.get_state(server)
        assert queued.active.turn_id == old.turn_id
        assert MapSet.size(queued.postponed_tokens) == 1

        {expected_count, expected_history, expected_revision, schedule_case} =
          if input["schedule"] == "cancel" do
            assert :ok = Server.cancel_turn(server, old.turn_id)
            assert {:error, :cancelled} = call_result(first)
            {0, [], 0, "LIFE-001/cancel-blocked"}
          else
            send(worker, {:release, first_gate})
            assert {:ok, committed} = call_result(first)
            assert committed.state == %{count: input["first"], history: ["first"]}
            assert {:error, :stale_turn} = Server.cancel_turn(server, old.turn_id)
            {input["first"], ["first"], 1, "LIFE-001/completion-before-cancel"}
          end

        root = old.exec_handle.pid
        assert_receive {:DOWN, ^root_ref, :process, ^root, _reason}, 2_000
        assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
        {second_worker, current, second_ref, second_root_ref} = blocked(server, key, second_gate)
        refute current.turn_id == old.turn_id
        assert Server.agent(server).state == %{count: expected_count, history: expected_history}
        assert Server.status(server).state_version == expected_revision

        # Use the actual completed/cancelled handle and timer, not an arbitrary ref.
        send(
          server,
          {:jido_exec_async_result, old.exec_handle.ref, root,
           {:ok, %{count: 999_999, history: ["stale"]}}}
        )

        send(server, {:DOWN, old.exec_handle.monitor_ref, :process, root, :normal})
        send(server, {:timeout, old.timeout_timer, {:turn_timeout, old.turn_id}})
        {:running, unchanged} = :sys.get_state(server)
        assert unchanged.active.turn_id == current.turn_id
        assert unchanged.agent.state == %{count: expected_count, history: expected_history}
        assert unchanged.state_version == expected_revision
        send(second_worker, {:release, second_gate})

        # This call waits behind the second Turn and gives a protocol completion barrier.
        assert {:ok, final} =
                 Server.call(server, runtime_signal("counter.add", %{by: 0, label: "barrier"}))

        assert final.state == %{
                 count: expected_count + input["second"],
                 history: expected_history ++ ["second", "barrier"]
               }

        assert Server.status(server).state_version == expected_revision + 2
        second_root = current.exec_handle.pid
        assert_receive {:DOWN, ^second_ref, :process, ^second_worker, _reason}, 2_000
        assert_receive {:DOWN, ^second_root_ref, :process, ^second_root, _reason}, 2_000
        [schedule_case, "LIFE-001/serial-admission", "LIFE-001/actual-stale-handle"]
      end
    end)
  end

  defp turn_attempt(jido, %{"steps" => steps}) do
    with_server(jido, fn server, _key ->
      {_model, _revision, observations} =
        steps
        |> Enum.with_index()
        |> Enum.reduce({%{count: 0, history: []}, 0, []}, fn {step, index},
                                                             {model, revision, seen} ->
          label = Integer.to_string(index)
          data = %{by: step["by"], label: label}

          data =
            if step["mode"] == "invalid_directive",
              do: Map.merge(data, %{test_pid: self(), directive_name: label}),
              else: data

          type = if step["mode"] == "success", do: "counter.add", else: "counter." <> step["mode"]
          result = Server.call(server, runtime_signal(type, data))

          {next, version, observed} =
            case step["mode"] do
              "success" ->
                expected = %{count: model.count + step["by"], history: model.history ++ [label]}
                assert {:ok, committed} = result
                assert committed.state == expected
                {expected, revision + 1, []}

              mode ->
                assert {:error, _reason} = result

                case_name =
                  case mode do
                    "failure" -> "TURN-003/execution-failure"
                    "invalid_state" -> "TURN-003/invalid-state"
                    "invalid_directive" -> "TURN-003/invalid-directive"
                  end

                extra =
                  if mode == "invalid_directive" do
                    assert_receive {:agent_action_ran, ^label, _worker}, 2_000
                    ["TURN-003/external-io-not-rolled-back"]
                  else
                    []
                  end

                {model, revision, [case_name | extra]}
            end

          assert Server.agent(server).state == next
          assert Server.status(server).state_version == version
          {next, version, seen ++ observed}
        end)

      # Always require success after the generated failure history.
      expected =
        Enum.reduce(steps, 0, fn step, sum ->
          if step["mode"] == "success", do: sum + step["by"], else: sum
        end)

      successful_labels =
        steps
        |> Enum.with_index()
        |> Enum.filter(fn {step, _} -> step["mode"] == "success" end)
        |> Enum.map(fn {_, index} -> Integer.to_string(index) end)

      assert {:ok, final} =
               Server.call(server, runtime_signal("counter.add", %{by: 1, label: "after"}))

      assert final.state == %{count: expected + 1, history: successful_labels ++ ["after"]}
      assert Server.status(server).state_version == length(successful_labels) + 1

      if Enum.any?(steps, &(&1["mode"] != "success")),
        do: observations ++ ["TURN-003/failure-then-success"],
        else: observations
    end)
  end
end
