defmodule Jido.AgentServer.AfterCommitTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Plugin.Commit

  alias JidoTest.CommitProjection.{
    Agent,
    Effect,
    First,
    ProjectionAgent,
    Second,
    Stateless,
    TimeoutAgent
  }

  setup do
    Process.register(self(), JidoTest.CommitProjection.Observer)
    handler = {__MODULE__, make_ref()}

    events =
      Enum.map([:start, :stop, :exception], &[:jido, :agent, :after_commit, &1]) ++
        [[:jido, :agent, :turn, :settled]]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        &__MODULE__.observe/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    start_supervised!(%{
      id: JidoTest.CommitProjection.Sink,
      start: {Elixir.Agent, :start_link, [fn -> [] end, [name: JidoTest.CommitProjection.Sink]]}
    })

    %{sink: JidoTest.CommitProjection.Sink}
  end

  def observe(event, measurements, %{agent_module: module} = metadata, owner)
      when module in [Agent, ProjectionAgent, TimeoutAgent],
      do: send(owner, {:observed, event, measurements, metadata})

  def observe(_event, _measurements, _metadata, _config), do: :ok

  test "notifies in declaration order, with exact owned revisions, before Directives", context do
    %{jido: jido, sink: sink} = context

    definition =
      definition([{First, [key: :first, sink: sink]}, {Second, [key: :second, sink: sink]}])

    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id(), debug: true)
    signal = update(3, [%Effect{sink: sink}])
    assert {:ok, committed} = Server.call(server, signal)
    assert committed.state == %{count: 3, first: 3, second: 3}
    settle(server, 1)

    assert [{:commit, First, nil, first}, {:commit, Second, nil, second}, :effect] = history(sink)
    assert %Commit{plugin_state: 3, state_version: 1, agent_module: Agent, jido: ^jido} = first
    assert first.agent_id == committed.id
    assert first.turn_id == second.turn_id
    assert second.plugin_state == 3
    assert second.state_version == 1

    assert Map.keys(Map.from_struct(first)) |> Enum.sort() ==
             Enum.sort(
               ~w(plugin turn_id agent_id agent_module plugin_state state_version jido partition)a
             )

    for package <- [First, Second] do
      assert_receive {:observed, [:jido, :agent, :after_commit, :start], %{state_version: 1},
                      start}

      assert start.plugin_module == package

      assert start.facet_module in [
               JidoTest.CommitProjection.ServerFacet,
               JidoTest.CommitProjection.NotificationFacet
             ]

      assert start.stage == :after_commit
      assert_receive {:observed, [:jido, :agent, :after_commit, :stop], stop_measurements, stop}
      assert start.turn_id == stop.turn_id
      assert start.plugin_module == stop.plugin_module
      assert stop.status == :ok
      assert is_integer(stop_measurements.duration)
      refute Map.has_key?(stop, :plugin_state)
      refute Map.has_key?(stop, :turn_context)
    end
  end

  test "unchanged Turns advance the revision and stateless hooks receive nil", %{
    jido: jido,
    sink: sink
  } do
    definition = definition([{Stateless, [sink: sink]}])
    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id())
    assert history(sink) == []

    for version <- 1..2 do
      assert {:ok, committed} = Server.call(server, update(0))
      assert committed.state == %{count: 0}
      settle(server, version)
    end

    assert [{:commit, Stateless, nil, first}, {:commit, Stateless, nil, second}] = history(sink)
    assert {first.plugin_state, first.state_version} == {nil, 1}
    assert {second.plugin_state, second.state_version} == {nil, 2}
    refute first.turn_id == second.turn_id
  end

  test "failed and direct Turns do not notify", %{jido: jido, sink: sink} do
    definition = definition([{First, [key: :first, sink: sink]}])
    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id())
    assert {:error, _} = Server.call(server, signal("projection.reject"))
    assert Server.snapshot(server).state_version == 0
    assert history(sink) == []

    assert {:ok, agent} = Jido.Agent.instantiate(definition)
    assert {:ok, candidate, []} = Jido.Agent.cmd(agent, update(4))
    assert candidate.state.first == 4
    assert history(sink) == []
  end

  test "hooks keep inspections responsive and serialize Turns", %{jido: jido, sink: sink} do
    observer = JidoTest.CommitProjection.Observer
    gate = unique_id()
    definition = definition([{First, [key: :first, sink: sink, observer: observer, gate: gate]}])
    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id())
    assert {:ok, committed} = Server.call(server, update(5))
    assert_receive {:commit_started, %Commit{state_version: 1}, worker}
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    assert Server.status(server).phase == :directing
    assert {:ok, 5} = Server.plugin_state(server, First)
    second = Task.async(fn -> Server.call(server, update(1)) end)
    send(worker, {:release, gate})
    assert {:ok, next} = Task.await(second)
    assert next.state.count == 6
    assert_receive {:commit_started, %Commit{state_version: 2}, worker2}
    send(worker2, {:release, gate})
    settle(server, 2)

    assert Enum.map(history(sink), fn {:commit, _, _, commit} -> commit.state_version end) == [
             1,
             2
           ]
  end

  test "a hook cannot call another Turn on its owner", %{jido: jido, sink: sink} do
    definition =
      definition([
        {First,
         [
           key: :first,
           sink: sink,
           observer: JidoTest.CommitProjection.Observer,
           result: :reentrant
         ]}
      ])

    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id())
    assert {:ok, committed} = Server.call(server, update(1))
    assert_receive {:reentrant_result, {:error, :reentrant_commit}}
    settle(server, 1)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  defmodule RejectedStorage do
    @moduledoc false
    @behaviour Jido.Persistence.Adapter
    defdelegate validate_options(opts), to: Jido.Persistence.ETS
    defdelegate get(key, opts), to: Jido.Persistence.ETS
    defdelegate put(key, value, opts), to: Jido.Persistence.ETS
    defdelegate delete(key, opts), to: Jido.Persistence.ETS

    def compare_and_swap(key, expected, value, opts) do
      if :erlang.binary_to_term(value, [:safe]).revision == 0,
        do: Jido.Persistence.ETS.compare_and_swap(key, expected, value, opts),
        else: {:error, {:rejected, :storage_unavailable}}
    end
  end

  test "storage rejection does not notify", %{jido: jido, sink: sink} do
    {_, opts} = persistence()
    persistence = {RejectedStorage, opts}
    id = unique_id()

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        id: id,
        persistence: persistence,
        restore: false
      )

    initial = Server.snapshot(server)
    ref = Process.monitor(server)
    assert {:error, {:persistence_failed, _}} = Server.call(server, update(1))
    assert_receive {:DOWN, ^ref, :process, ^server, _}

    assert {:ok, saved, 0} =
             Jido.Persistence.load_agent_with_revision(persistence, Agent, id, instance: jido)

    assert saved == initial.agent
    assert history(sink) == []
  end

  for result <- [:error, :raise, :throw, :exit, :kill, :invalid] do
    @result result
    test "#{result} settles after commit and skips remaining hooks and Directives", %{
      jido: jido,
      sink: sink
    } do
      observer = self()

      policy = fn reason, outcome ->
        send(observer, {:policy, reason, outcome})
        :continue
      end

      definition =
        definition([
          {First, [key: :first, sink: sink, result: @result]},
          {Second, [key: :second, sink: sink]}
        ])

      {:ok, server} = Jido.start_agent(jido, definition, id: unique_id(), error_policy: policy)
      assert {:ok, committed} = Server.call(server, update(7, [%Effect{sink: sink}]))
      assert_receive {:policy, reason, outcome}, 2_000
      assert outcome.stage == :after_commit
      assert outcome.status == :failed
      assert outcome.committed?
      assert outcome.state_version_after == 1
      assert outcome.error == reason

      assert outcome.directives == %{
               total: 1,
               completed: 0,
               failed: 0,
               skipped: 1,
               failed_index: nil
             }

      settle(server, 1)
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
      assert [{:commit, First, nil, _}] = history(sink)
      assert_receive {:observed, [:jido, :agent, :after_commit, :start], _, start}
      assert_receive {:observed, event, _, stop}

      assert event in [
               [:jido, :agent, :after_commit, :stop],
               [:jido, :agent, :after_commit, :exception]
             ]

      assert start.turn_id == stop.turn_id
      assert start.plugin_module == stop.plugin_module
      assert stop.status == :error
      refute inspect(stop) =~ "private projection error"
    end
  end

  test "timeout kills the task and preserves the saved commit", %{jido: jido} do
    observer = JidoTest.CommitProjection.Observer

    policy = fn reason, outcome ->
      send(observer, {:policy, reason, outcome})
      :continue
    end

    persistence = persistence()
    id = unique_id()

    {:ok, server} =
      Jido.start_agent(jido, TimeoutAgent,
        id: id,
        persistence: persistence,
        restore: false,
        directive_timeout: 100,
        error_policy: policy
      )

    assert {:ok, committed} = Server.call(server, update(9))
    assert_receive {:commit_started, _, worker}
    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 2_000

    assert_receive {:policy, %Jido.Error.TimeoutError{},
                    %{stage: :after_commit, status: :timed_out, committed?: true}}

    settle(server, 1)

    assert {:ok, saved, 1} =
             Jido.Persistence.load_agent_with_revision(persistence, TimeoutAgent, id,
               instance: jido
             )

    assert saved.state == committed.state
  end

  test "runtime replacement and restore rebuild the exact view without replay", %{jido: jido} do
    persistence = persistence()
    id = unique_id()

    {:ok, server} =
      Jido.start_agent(jido, ProjectionAgent,
        id: id,
        persistence: persistence,
        restore: false,
        restart: :temporary
      )

    assert_receive {:projection_init, runtime, %{plugin_state: 0, state_version: 0}}
    assert {:ok, _} = Server.call(server, update(4))
    settle(server, 1)
    assert GenServer.call(runtime, :view) == {4, 1}
    ref = Process.monitor(runtime)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^ref, :process, ^runtime, :killed}
    assert_receive {:projection_init, replacement, %{plugin_state: 4, state_version: 1}}, 2_000
    assert {:ok, committed} = Server.call(server, update(2))
    settle(server, 2)
    assert GenServer.call(replacement, :view) == {6, 2}
    assert :ok = Server.stop(server)

    {:ok, restored} =
      Jido.start_agent(jido, ProjectionAgent,
        id: id,
        persistence: persistence,
        restore: :required,
        restart: :temporary
      )

    assert_receive {:projection_init, restored_runtime, %{plugin_state: 6, state_version: 2}}
    assert Server.snapshot(restored).agent.state == committed.state
    assert GenServer.call(restored_runtime, :view) == {6, 2}
    assert Server.status(restored).phase == :idle
  end

  test "infinity still bounds a hook and old task messages cannot settle a later Turn", %{
    jido: jido
  } do
    {:ok, server} =
      Jido.start_agent(jido, TimeoutAgent, id: unique_id(), directive_timeout: :infinity)

    assert {:ok, _} = Server.call(server, update(1))
    assert_receive {:commit_started, _, first_worker}
    assert {:directing, %{commit_task: first}} = :sys.get_state(server)
    assert remaining = :erlang.read_timer(first.timer)
    assert remaining in 1..5_000
    send(first_worker, {:release, "timeout"})
    settle(server, 1)

    assert {:ok, committed} = Server.call(server, update(1))
    assert_receive {:commit_started, _, second_worker}
    send(server, {first.task.ref, :ok})
    send(server, {:timeout, first.timer, {:after_commit_timeout, first.task.ref}})
    send(server, {:DOWN, first.task.ref, :process, first_worker, :normal})
    assert Server.snapshot(server) == %{agent: committed, state_version: 2}
    assert Server.status(server).phase == :directing
    send(second_worker, {:release, "timeout"})
    settle(server, 2)
  end

  test "hard owner loss kills a hook and restore does not replay it", %{jido: jido, sink: sink} do
    persistence = persistence()
    id = unique_id()

    {:ok, server} =
      Jido.start_agent(jido, TimeoutAgent,
        id: id,
        persistence: persistence,
        restore: false,
        restart: :temporary,
        directive_timeout: :infinity
      )

    assert {:ok, committed} = Server.call(server, update(8))
    assert_receive {:commit_started, _, worker}
    server_ref = Process.monitor(server)
    worker_ref = Process.monitor(worker)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _}
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)

    {:ok, restored} =
      Jido.start_agent(jido, TimeoutAgent,
        id: id,
        persistence: persistence,
        restore: :required,
        restart: :temporary
      )

    assert Server.snapshot(restored) == %{agent: committed, state_version: 1}
    assert Server.status(restored).phase == :idle
    assert [{:commit, First, nil, _}] = history(sink)
  end

  test "stop-on-error stops after the caller receives the successful commit", %{
    jido: jido,
    sink: sink
  } do
    definition = definition([{First, key: :first, sink: sink, result: :error}])

    {:ok, server} =
      Jido.start_agent(jido, definition,
        id: unique_id(),
        restart: :temporary,
        error_policy: :stop_on_error
      )

    ref = Process.monitor(server)
    assert {:ok, committed} = Server.call(server, update(6))
    assert committed.state == %{count: 6, first: 6}

    assert_receive {:DOWN, ^ref, :process, ^server,
                    {:shutdown, {:agent_error, :projection_unavailable}}}

    assert_receive {:observed, [:jido, :agent, :turn, :settled], _,
                    %{stage: :after_commit, committed?: true, status: :error}}
  end

  test "hook failure logs contain bounded identity and no raw callback error", %{
    jido: jido,
    sink: sink
  } do
    definition = definition([{First, key: :first, sink: sink, result: :raise}])
    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id())

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, _} = Server.call(server, update(1))
        settle(server, 1)
      end)

    assert log =~ "Agent Plugin commit notification failed"
    refute log =~ "private projection error"
    refute log =~ "RuntimeError"
  end

  test "owner shutdown kills a blocked task and balances its span", %{jido: jido, sink: sink} do
    definition =
      definition([
        {First,
         [
           key: :first,
           sink: sink,
           observer: JidoTest.CommitProjection.Observer,
           gate: unique_id()
         ]}
      ])

    {:ok, server} = Jido.start_agent(jido, definition, id: unique_id(), restart: :temporary)
    assert {:ok, _} = Server.call(server, update(1))
    assert_receive {:commit_started, _, worker}
    ref = Process.monitor(worker)
    assert :ok = Server.stop(server)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}
    assert_receive {:observed, [:jido, :agent, :after_commit, :start], _, start}
    assert_receive {:observed, [:jido, :agent, :after_commit, :stop], _, stop}
    assert start.turn_id == stop.turn_id
    assert start.plugin_module == stop.plugin_module
    assert stop.status == :error

    assert_receive {:observed, [:jido, :agent, :turn, :settled], _,
                    %{stage: :after_commit, committed?: true}}
  end

  defp definition(plugins), do: %{Agent.definition() | plugins: plugins}

  defp update(amount, directives \\ []),
    do: signal("projection.update", %{amount: amount, directives: directives})

  defp history(sink), do: Elixir.Agent.get(sink, & &1)

  defp settle(server, version) do
    assert_receive {:observed, [:jido, :agent, :turn, :settled], %{state_version_after: ^version},
                    _},
                   2_000

    assert Server.status(server).phase == :idle
  end

  defp persistence do
    {Jido.Persistence.ETS, table: :"commit_projection_#{System.unique_integer([:positive])}"}
  end
end
