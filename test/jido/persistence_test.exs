defmodule JidoTest.PersistenceTest do
  use JidoTest.Case, async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias Jido.Persistence.ETS
  alias Jido.Signal
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent

  defmodule RaisingAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(_key, opts) do
      if Keyword.get(opts, :allow_read),
        do: {:error, :not_found},
        else: raise("persistence read failed")
    end

    @impl true
    def put(_key, _value, _opts), do: raise("persistence write failed")

    @impl true
    def compare_and_swap(_key, _expected, _value, _opts), do: raise("persistence write failed")

    @impl true
    def delete(_key, _opts), do: raise("persistence delete failed")
  end

  defmodule ReplyAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(_key, opts), do: Keyword.get(opts, :get_reply, Keyword.fetch!(opts, :reply))

    @impl true
    def put(_key, _value, opts), do: Keyword.fetch!(opts, :reply)

    @impl true
    def compare_and_swap(_key, _expected, _value, opts), do: Keyword.fetch!(opts, :reply)

    @impl true
    def delete(_key, opts), do: Keyword.fetch!(opts, :reply)
  end

  defmodule BarrierAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def get(key, opts) do
      result = ETS.get(key, opts)
      send(Keyword.fetch!(opts, :observer), {:read, self(), result})

      receive do
        :write -> result
      after
        5_000 -> {:error, :barrier_timeout}
      end
    end

    @impl true
    defdelegate put(key, value, opts), to: ETS
    @impl true
    defdelegate compare_and_swap(key, expected, value, opts), to: ETS
    @impl true
    defdelegate delete(key, opts), to: ETS
  end

  defp adapter(name) do
    {ETS, table: :"agent_persistence_#{name}_#{System.unique_integer([:positive])}"}
  end

  test "restores portable Plugin state and rebuilds its runtime", %{jido: jido} do
    persistence = adapter(:plugin_state)
    tick = Signal.new!("cron.tick", %{}, source: "/test")
    spec = Jido.Plugin.Scheduler.build_cron_spec("* * * * * * *", tick)

    agent =
      RuntimeAgent.new!(
        id: unique_id("persisted"),
        state: %{events: [:saved], ticks: 4, scheduler: %{cron: %{heartbeat: spec}}}
      )

    assert :ok = Persistence.save_agent(persistence, agent)
    assert {:ok, restored} = Persistence.load_agent(persistence, RuntimeAgent, agent.id)

    assert restored == agent
    assert {:ok, pid} = Jido.start_agent(jido, restored)
    assert Map.has_key?(Server.agent(pid).state.scheduler.cron, :heartbeat)

    eventually(fn -> Server.agent(pid).state.ticks > 4 end, timeout: 5_000)
  end

  test "contains adapter faults and keeps a live Server running", %{jido: jido} do
    agent = RuntimeAgent.new!(id: unique_id("persistence-fault"))

    assert {:error, %Jido.Error.ExecutionError{}} =
             Persistence.save_agent(RaisingAdapter, agent)

    assert {:error, %Jido.Error.ExecutionError{details: %{operation: :compare_and_swap}}} =
             Persistence.save_agent({RaisingAdapter, allow_read: true}, agent)

    assert {:error, %Jido.Error.ExecutionError{details: %{operation: :get}}} =
             Persistence.load_agent(RaisingAdapter, RuntimeAgent, agent.id)

    assert {:error, %Jido.Error.ExecutionError{details: %{operation: :delete}}} =
             Persistence.delete_agent(RaisingAdapter, RuntimeAgent, agent.id)

    {:ok, pid} =
      Jido.start_agent(jido, agent,
        persistence: {RaisingAdapter, allow_read: true},
        restore: false
      )

    assert {:error, %Jido.Error.ExecutionError{}} = Server.hibernate(pid)
    assert Process.alive?(pid)
    assert Server.agent(pid) == agent
  end

  test "validates adapter replies before fault containment returns a result" do
    agent = RuntimeAgent.new!(id: unique_id("adapter-reply"))

    operations = [
      get: &Persistence.load_agent(&1, RuntimeAgent, agent.id),
      compare_and_swap: &Persistence.save_agent(&1, agent),
      delete: &Persistence.delete_agent(&1, RuntimeAgent, agent.id)
    ]

    for {operation, call} <- operations do
      opts = if operation == :compare_and_swap, do: [get_reply: {:error, :not_found}], else: []

      for reply <- [:invalid, {:ok, %{invalid: :record}}] do
        assert {:error, %Jido.Error.ExecutionError{} = error} =
                 call.({ReplyAdapter, Keyword.put(opts, :reply, reply)})

        assert error.message == "Persistence adapter returned an invalid result"
        assert error.details == %{operation: operation, result: reply}
      end

      assert {:error, :unavailable} =
               call.({ReplyAdapter, Keyword.put(opts, :reply, {:error, :unavailable})})
    end
  end

  test "writes every successful commit and preserves the Server revision", %{jido: jido} do
    persistence = adapter(:commit)
    id = unique_id("commit")

    {:ok, pid} =
      Jido.start_agent(jido, RuntimeAgent,
        id: id,
        persistence: persistence,
        restore: false
      )

    assert {:ok, agent} =
             Server.call(pid, Signal.new!("runtime.record", %{event: :saved}, source: "/test"))

    assert agent.state.events == [:saved]

    assert {:ok, restored, 1} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, id, instance: jido)

    assert restored.state.events == [:saved]
  end

  test "hibernate persists and stops an idle Agent Server", %{jido: jido} do
    persistence = adapter(:hibernate)
    id = unique_id("hibernate")

    {:ok, pid} =
      Jido.start_agent(jido, RuntimeAgent,
        id: id,
        persistence: persistence,
        restore: false
      )

    assert {:ok, _agent} =
             Server.call(pid, Signal.new!("runtime.record", %{event: :saved}, source: "/test"))

    monitor = Process.monitor(pid)
    assert :ok = Server.hibernate(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :hibernate}}, 1_000

    assert {:ok, restored} =
             Persistence.load_agent(persistence, RuntimeAgent, id, instance: jido)

    assert restored.state.events == [:saved]
  end

  test "a stale Server cannot commit, dispatch, hibernate, or overwrite on stop", %{jido: jido} do
    persistence = adapter(:stale_server)
    agent = RuntimeAgent.new!(id: unique_id("stale-server"))
    observer = self()

    policy = fn reason, outcome ->
      send(observer, {:failed_commit, reason, outcome})
      :continue
    end

    opts = [persistence: persistence, restore: false, error_policy: policy]
    assert {:ok, stale} = Jido.start_agent(jido, agent, opts)
    committed = %{agent | state: %{agent.state | events: [:winner]}}

    assert :ok =
             Persistence.save_agent(persistence, committed,
               instance: jido,
               revision: 1,
               expected_revision: 0
             )

    output = Signal.new!("persistence.output", %{}, source: "/test")

    command =
      Signal.new!(
        "runtime.directive",
        %{event: :stale, directive: Jido.Agent.Directive.emit_to_pid(output, self())},
        source: "/test"
      )

    assert {:error, {:persistence_failed, :conflict}} = Server.call(stale, command)

    assert_receive {:failed_commit, {:persistence_failed, :conflict},
                    %Jido.Agent.Turn.Outcome{
                      stage: :commit,
                      committed?: false,
                      state_version_before: 0
                    }}

    assert Server.snapshot(stale) == %{agent: agent, state_version: 0}
    refute_receive {:signal, ^output}
    assert {:error, :conflict} = Server.hibernate(stale)
    assert Process.alive?(stale)

    monitor = Process.monitor(stale)
    assert :ok = Server.stop(stale)
    assert_receive {:DOWN, ^monitor, :process, ^stale, _reason}

    assert {:ok, ^committed, 1} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id,
               instance: jido
             )
  end

  test "thaw restores, starts, and rebuilds Plugin runtimes", %{jido: jido} do
    persistence = adapter(:thaw)
    id = unique_id("thaw")
    agent = RuntimeAgent.new!(id: id, state: %{events: [:saved], ticks: 2})

    assert :ok =
             Persistence.save_agent(persistence, agent,
               instance: jido,
               revision: 7,
               reason: :hibernate
             )

    assert {:ok, pid} =
             Jido.thaw(jido, RuntimeAgent, id, persistence: persistence)

    assert Server.agent(pid).state.events == [:saved]
    assert %{state_version: 7} = Server.snapshot(pid)

    assert {:ok, _agent} =
             Server.call(pid, Signal.new!("runtime.record", %{event: :next}, source: "/test"))

    assert {:ok, _restored, 8} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, id, instance: jido)
  end

  test "a normal start restores a record when one exists", %{jido: jido} do
    persistence = adapter(:automatic_restore)
    id = unique_id("automatic-restore")
    agent = RuntimeAgent.new!(id: id, state: %{events: [:saved]})

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido, revision: 3)
    assert {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id, persistence: persistence)
    assert Server.agent(pid).state.events == [:saved]
    assert %{state_version: 3} = Server.snapshot(pid)
  end

  test "deletes one persisted Agent", %{jido: jido} do
    persistence = adapter(:delete)
    agent = RuntimeAgent.new!(id: unique_id("delete"))

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido)
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, agent.id, instance: jido)

    assert {:error, :not_found} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id, instance: jido)
  end

  test "rejects an invalid persistence record" do
    {ETS, opts} = persistence = adapter(:invalid_record)
    agent = RuntimeAgent.new!(id: unique_id("invalid-record"))
    key = Persistence.agent_key(nil, RuntimeAgent, agent.id)

    assert :ok = ETS.put(key, <<0, 1, 2>>, opts)

    assert {:error, :invalid_persistence_record} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id)

    assert {:error, :invalid_persistence_record} =
             Persistence.save_agent(persistence, agent, revision: 1)

    assert {:ok, <<0, 1, 2>>} = ETS.get(key, opts)
  end

  test "rejects stale revisions and different state at the same revision" do
    persistence = adapter(:revisions)
    agent = RuntimeAgent.new!(id: unique_id("revisions"), state: %{events: [:saved]})
    changed = %{agent | state: %{agent.state | events: [:changed]}}

    assert :ok = Persistence.save_agent(persistence, agent, revision: 2)
    assert :ok = Persistence.save_agent(persistence, agent, revision: 2, expected_revision: 2)

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, agent, revision: 2, expected_revision: 1)

    for revision <- [0, 1, 2] do
      assert {:error, :conflict} =
               Persistence.save_agent(persistence, changed, revision: revision)
    end

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, changed, revision: 3, expected_revision: 1)

    assert {:ok, ^agent, 2} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id)

    assert :ok = Persistence.save_agent(persistence, changed, revision: 3, expected_revision: 2)
  end

  test "requires the expected record and validates the expected revision" do
    persistence = adapter(:expected)
    agent = RuntimeAgent.new!(id: unique_id("expected"))

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, agent, revision: 2, expected_revision: 1)

    for invalid <- [-1, nil, "0"] do
      assert {:error, {:invalid_expected_revision, ^invalid}} =
               Persistence.save_agent(persistence, agent, expected_revision: invalid)
    end

    assert :ok = Persistence.save_agent(persistence, agent, revision: 1, expected_revision: 0)
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, agent.id)

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, agent, revision: 2, expected_revision: 1)
  end

  test "only one writer commits when both read the same durable value" do
    for initial_revision <- [0, 1] do
      {ETS, opts} = persistence = adapter(:race)
      agent = RuntimeAgent.new!(id: unique_id("race"))

      if initial_revision == 1 do
        assert :ok = Persistence.save_agent(persistence, agent, revision: 1)
      end

      guarded = {BarrierAdapter, Keyword.put(opts, :observer, self())}

      tasks =
        for event <- [:first, :second] do
          candidate = %{agent | state: %{agent.state | events: [event]}}

          Task.async(fn ->
            result =
              Persistence.save_agent(guarded, candidate,
                revision: initial_revision + 1,
                expected_revision: initial_revision
              )

            {result, candidate}
          end)
        end

      assert_receive {:read, first, observed}
      assert_receive {:read, second, ^observed}
      send(first, :write)
      send(second, :write)

      results = Enum.map(tasks, &Task.await/1)
      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert [{{:error, :conflict}, _loser}] = Enum.reject(results, &match?({:ok, _}, &1))

      revision = initial_revision + 1

      assert {:ok, ^winner, ^revision} =
               Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id)
    end
  end

  test "a live Server snapshot exposes no private process references", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("snapshot"))

    assert %{agent: %Agent{}, state_version: 0} = Server.snapshot(pid)

    snapshot = Server.snapshot(pid)
    refute Map.has_key?(snapshot, :children)
    refute Map.has_key?(snapshot, :active)
    refute Map.has_key?(snapshot, :runtime)
  end
end
