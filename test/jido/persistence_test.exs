defmodule Jido.PersistenceTest do
  use Jido.Test.Case, async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias Jido.Persistence.ETS
  alias Jido.Signal
  alias Jido.Test.AgentServer.RuntimeFixtures.RuntimeAgent
  alias Jido.Test.AgentServer.ScheduledOccurrenceFixtures.{Clock, FastRuntimeAgent}

  defmodule ConfiguredInstance do
    def __jido_persistence__, do: {ETS, table: __MODULE__}
  end

  defmodule DisabledInstance do
    def __jido_persistence__, do: nil
  end

  defmodule InvalidInstance do
    def __jido_persistence__, do: {:invalid, :options}
  end

  defmodule RaisingInstance do
    def __jido_persistence__, do: raise("invalid instance config")
  end

  defmodule CheckpointAgent do
    use Jido.Agent, name: "checkpoint_contract"

    state do
      schema Jido.Joi.object(%{reply: Jido.Joi.any()})
    end

    @impl true
    def checkpoint(agent, _context), do: agent.state.reply
  end

  defmodule RestoreAgent do
    use Jido.Agent, name: "restore_initializer"
    def initialize(%{create: true}, _context), do: {:ok, %{}}
    def initialize(_, _context), do: raise("initialize/2 ran during restore")
  end

  test "instance sources use their live namespace and honor explicit overrides" do
    start_supervised!(
      {Jido, name: ConfiguredInstance, namespace: "configured", persistence: ConfiguredInstance.__jido_persistence__()},
      id: ConfiguredInstance
    )

    agent = RuntimeAgent.instantiate!(id: unique_id("namespace"))
    direct = ConfiguredInstance.__jido_persistence__()

    for {opts, namespace} <- [{[], "configured"}, {[namespace: "override"], "override"}] do
      assert :ok = Persistence.save_agent(ConfiguredInstance, agent, opts)

      assert {:ok, ^agent} =
               Persistence.load_agent(direct, RuntimeAgent, agent.id, namespace: namespace)

      assert {:ok, ^agent} =
               Persistence.load_agent(ConfiguredInstance, RuntimeAgent, agent.id, opts)

      assert :ok = Persistence.delete_agent(ConfiguredInstance, RuntimeAgent, agent.id, opts)

      assert {:error, :deleted} =
               Persistence.load_agent(direct, RuntimeAgent, agent.id, namespace: namespace)
    end
  end

  test "source resolution preserves disabled and invalid configuration errors" do
    agent = RuntimeAgent.instantiate!(id: unique_id("config"))

    for call <- [
          &Persistence.save_agent(&1, agent, namespace: "persistence-test"),
          &Persistence.load_agent(&1, RuntimeAgent, agent.id, namespace: "persistence-test"),
          &Persistence.delete_agent(&1, RuntimeAgent, agent.id, namespace: "persistence-test")
        ] do
      for source <- [nil, false, :inherit, DisabledInstance] do
        assert {:error, :persistence_not_configured} = call.(source)
      end

      for source <- [InvalidInstance, RaisingInstance, {:invalid, :options}] do
        assert {:error, {:invalid_persistence_config, _}} = call.(source)
      end

      assert {:error, {:invalid_persistence_adapter, String}} = call.(String)
    end
  end

  test "configuration resolution supports inherited and explicit adapters" do
    configured = {ETS, table: ConfiguredInstance}

    configured_profile = %Jido.Persistence.Config{
      store: configured,
      codec: Jido.Persistence.Codec.Term
    }

    assert {:ok, ^configured_profile} = Persistence.resolve_config(:inherit, ConfiguredInstance)
    assert {:ok, nil} = Persistence.resolve_config(:inherit, DisabledInstance)
    assert {:ok, nil} = Persistence.resolve_config(:inherit, nil)

    assert {:ok, %Jido.Persistence.Config{store: {ETS, []}}} =
             Persistence.resolve_config(ETS, ConfiguredInstance)

    assert {:ok, nil} = Persistence.resolve_config(false, ConfiguredInstance)
  end

  test "public operations reject non-keyword options before adapter work" do
    agent = RuntimeAgent.instantiate!(id: unique_id("invalid-options"))
    persistence = adapter(:invalid_options)

    for opts <- [[:not_keyword], %{"revision" => 1}] do
      assert {:error, {:invalid_persistence_options, ^opts}} =
               Persistence.save_agent(persistence, agent, opts)

      assert {:error, {:invalid_persistence_options, ^opts}} =
               Persistence.load_agent(persistence, RuntimeAgent, agent.id, opts)

      assert {:error, {:invalid_persistence_options, ^opts}} =
               Persistence.delete_agent(persistence, RuntimeAgent, agent.id, opts)
    end
  end

  test "checkpoint callback failures and invalid revisions cannot write a record" do
    persistence = adapter(:callback)

    for reply <- [{:ok, :invalid}, {:ok, %URI{}}, {:error, :checkpoint_failed}] do
      agent = CheckpointAgent.instantiate!(id: unique_id("callback"), state: %{reply: reply})

      case reply do
        {:ok, _invalid} ->
          assert {:error, %{code: :invalid_map}} =
                   Persistence.save_agent(persistence, agent, namespace: "persistence-test")

        {:error, reason} ->
          assert {:error, ^reason} =
                   Persistence.save_agent(persistence, agent, namespace: "persistence-test")
      end

      assert {:error, :not_found} =
               Persistence.load_agent(persistence, CheckpointAgent, agent.id, namespace: "persistence-test")
    end

    agent = RuntimeAgent.instantiate!(id: unique_id("revision"))

    for revision <- [-1, nil, "0"] do
      assert {:error, {:invalid_checkpoint, :shape}} =
               Persistence.save_agent(persistence, agent,
                 namespace: "persistence-test",
                 revision: revision
               )
    end

    assert {:error, :not_found} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id, namespace: "persistence-test")
  end

  defmodule RaisingAdapter do
    @behaviour Jido.Persistence.Store

    @impl true
    def validate_options(opts) do
      if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:allow_read] == [] and
           Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)),
         do: :ok,
         else: {:error, :invalid_options}
    end

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
    @behaviour Jido.Persistence.Store

    @impl true
    def validate_options(opts) do
      if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:get_reply, :reply] == [] and
           Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)),
         do: :ok,
         else: {:error, :invalid_options}
    end

    @impl true
    def get(_key, opts), do: Keyword.get(opts, :get_reply, Keyword.fetch!(opts, :reply))

    @impl true
    def put(_key, _value, opts), do: Keyword.fetch!(opts, :reply)

    @impl true
    def compare_and_swap(_key, _expected, _value, opts), do: Keyword.fetch!(opts, :reply)

    @impl true
    def delete(_key, opts), do: Keyword.fetch!(opts, :reply)
  end

  defmodule CASFaultAdapter do
    @behaviour Jido.Persistence.Store

    @impl true
    def validate_options(opts) do
      if Keyword.keyword?(opts) and Keyword.keys(opts) == [:mode],
        do: :ok,
        else: {:error, :invalid_options}
    end

    @impl true
    def get(_key, _opts), do: {:error, :not_found}

    @impl true
    def compare_and_swap(_key, _expected, _value, opts) do
      case Keyword.fetch!(opts, :mode) do
        :raise -> raise "CAS raised"
        :throw -> throw(:cas_threw)
        :exit -> exit(:cas_exited)
      end
    end

    @impl true
    def delete(_key, _opts), do: :ok
  end

  defmodule BarrierAdapter do
    @behaviour Jido.Persistence.Store

    @impl true
    def validate_options(opts) do
      if Keyword.keyword?(opts) and Keyword.keys(opts) -- [:observer, :table] == [] and
           Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)),
         do: ETS.validate_options(Keyword.delete(opts, :observer)),
         else: {:error, :invalid_options}
    end

    @impl true
    def get(key, opts) do
      result = ETS.get(key, Keyword.delete(opts, :observer))
      send(Keyword.fetch!(opts, :observer), {:read, self(), result})

      receive do
        :write -> result
      after
        5_000 -> {:error, :barrier_timeout}
      end
    end

    @impl true
    def put(key, value, opts), do: ETS.put(key, value, Keyword.delete(opts, :observer))
    @impl true
    def compare_and_swap(key, expected, value, opts),
      do: ETS.compare_and_swap(key, expected, value, Keyword.delete(opts, :observer))

    @impl true
    def delete(key, opts), do: ETS.delete(key, Keyword.delete(opts, :observer))
  end

  defp adapter(name) do
    {ETS, table: :"agent_persistence_#{name}_#{System.unique_integer([:positive])}"}
  end

  defp persistent_instance(persistence) do
    id = System.unique_integer([:positive])
    name = :"persistence_instance_#{id}"

    start_supervised!(
      {Jido, name: name, namespace: "test/persistence/#{id}", persistence: persistence},
      id: {Jido, name}
    )

    name
  end

  test "public persistence operations emit bounded semantic spans" do
    persistence = adapter(:semantic_events)
    agent = RuntimeAgent.instantiate!(id: unique_id("semantic-persistence"))
    namespace = "test/persistence"

    events = [
      [:jido, :persistence, :operation, :start],
      [:jido, :persistence, :operation, :stop],
      [:jido, :persistence, :operation, :exception]
    ]

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, owner ->
          send(owner, {:persistence_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    opts = [namespace: namespace, partition: "west"]
    assert :ok = Persistence.save_agent(persistence, agent, opts)

    assert {:ok, ^agent, 0} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id, opts)

    assert :ok =
             Persistence.save_agent(
               persistence,
               %{agent | state: %{agent.state | events: [:saved]}},
               opts ++ [revision: 1, expected_revision: 0]
             )

    assert {:error, :conflict} =
             Persistence.save_agent(
               persistence,
               agent,
               opts ++ [revision: 2, expected_revision: 0]
             )

    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, agent.id, opts)

    assert {:error, :deleted} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id, opts)

    observed = collect_persistence_events([])
    starts = Enum.filter(observed, &(elem(&1, 0) == :start))
    stops = Enum.filter(observed, &(elem(&1, 0) == :stop))
    assert length(starts) == 6
    assert length(stops) == 6

    assert Enum.map(stops, fn {_ending, metadata, _measurements} ->
             {metadata.operation, metadata.status}
           end) == [
             {:compare_and_swap, :ok},
             {:load, :ok},
             {:compare_and_swap, :ok},
             {:compare_and_swap, :conflict},
             {:delete, :ok},
             {:load, :not_found}
           ]

    for {_ending, metadata, measurements} <- observed do
      assert metadata.schema_version == 1
      assert metadata.agent_namespace == namespace
      assert metadata.agent_partition == "west"
      assert metadata.agent_id == agent.id
      assert metadata.adapter_module == ETS
      assert metadata.persistence_reason == :manual
      refute Map.has_key?(metadata, :record)
      refute Map.has_key?(metadata, :key)
      assert Enum.all?(Map.values(measurements), &is_integer/1)
    end

    assert Enum.any?(stops, fn {_ending, metadata, measurements} ->
             metadata.operation == :compare_and_swap and metadata.status == :ok and
               measurements[:revision_after] == 1
           end)
  end

  defp collect_persistence_events(acc) do
    receive do
      {:persistence_event, event, measurements, metadata} ->
        collect_persistence_events([
          {List.last(event), metadata, measurements} | acc
        ])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "restores portable Plugin state and rebuilds its runtime", %{jido: jido} do
    start_supervised!(Clock)
    persistence = adapter(:plugin_state)
    tick = Signal.new!("cron.tick", %{}, source: "/test")
    spec = Jido.Plugin.Scheduler.CronRules.build_spec("* * * * * * *", tick)

    agent =
      FastRuntimeAgent.instantiate!(
        id: unique_id("persisted"),
        state: %{events: [:saved], ticks: 4, scheduler: %{cron: %{heartbeat: spec}}}
      )

    assert :ok = Persistence.save_agent(persistence, agent, namespace: "persistence-test")

    assert {:ok, restored} =
             Persistence.load_agent(persistence, FastRuntimeAgent, agent.id, namespace: "persistence-test")

    assert restored == agent
    assert {:ok, pid} = Jido.Test.AgentServer.Assertions.start_agent(jido, restored)
    assert Map.has_key?(Server.snapshot(pid).agent.state.scheduler.cron, :heartbeat)

    eventually(fn -> Server.snapshot(pid).agent.state.ticks > 4 end, timeout: 5_000)
  end

  test "contains adapter faults and reports indeterminate writes" do
    agent = RuntimeAgent.instantiate!(id: unique_id("persistence-fault"))

    assert {:error, %Jido.Error.ExecutionError{} = error} =
             Persistence.save_agent(RaisingAdapter, agent, namespace: "persistence-test")

    assert Jido.Error.code(error) == :persistence_callback_failed

    assert {:error, {:indeterminate, %Jido.Error.ExecutionError{details: %{operation: :compare_and_swap}} = error}} =
             Persistence.save_agent({RaisingAdapter, allow_read: true}, agent, namespace: "persistence-test")

    assert Jido.Error.code(error) == :persistence_callback_failed

    assert {:error, %Jido.Error.ExecutionError{details: %{operation: :get}} = error} =
             Persistence.load_agent(RaisingAdapter, RuntimeAgent, agent.id, namespace: "persistence-test")

    assert Jido.Error.code(error) == :persistence_callback_failed

    assert {:error, %Jido.Error.ExecutionError{details: %{operation: :delete}} = error} =
             Persistence.delete_agent(RaisingAdapter, RuntimeAgent, agent.id, namespace: "persistence-test")

    assert Jido.Error.code(error) == :persistence_callback_failed
  end

  test "validates adapter replies before fault containment returns a result" do
    agent = RuntimeAgent.instantiate!(id: unique_id("adapter-reply"))

    operations = [
      get: &Persistence.load_agent(&1, RuntimeAgent, agent.id, namespace: "persistence-test"),
      compare_and_swap: &Persistence.save_agent(&1, agent, namespace: "persistence-test"),
      delete: &Persistence.delete_agent(&1, RuntimeAgent, agent.id, namespace: "persistence-test")
    ]

    for {operation, call} <- operations do
      opts = if operation == :compare_and_swap, do: [get_reply: {:error, :not_found}], else: []

      for reply <- [:invalid, {:ok, %{invalid: :record}}] do
        result = call.({ReplyAdapter, Keyword.put(opts, :reply, reply)})

        error =
          case operation do
            :compare_and_swap ->
              assert {:error, {:indeterminate, %Jido.Error.ExecutionError{} = error}} = result
              error

            _operation ->
              assert {:error, %Jido.Error.ExecutionError{} = error} = result
              error
          end

        assert error.message == "Persistence adapter returned an invalid result"

        callback_operation = if operation == :delete, do: :get, else: operation

        assert error.details == %{
                 code: :persistence_invalid_callback_result,
                 operation: callback_operation,
                 result: reply
               }
      end

      result = call.({ReplyAdapter, Keyword.put(opts, :reply, {:error, :unavailable})})

      if operation == :compare_and_swap do
        assert {:error, {:indeterminate, :unavailable}} = result
      else
        assert {:error, :unavailable} = result
      end
    end
  end

  test "classifies the closed CAS result set" do
    agent = RuntimeAgent.instantiate!(id: unique_id("cas-results"))

    for {reply, expected} <- [
          {{:error, :conflict}, :conflict},
          {{:error, {:rejected, :too_large}}, {:rejected, :too_large}},
          {{:error, :indeterminate}, :indeterminate},
          {{:error, {:indeterminate, :timeout}}, {:indeterminate, :timeout}},
          {{:error, :unavailable}, {:indeterminate, :unavailable}}
        ] do
      assert {:error, ^expected} =
               Persistence.save_agent(
                 {ReplyAdapter, get_reply: {:error, :not_found}, reply: reply},
                 agent,
                 namespace: "persistence-test"
               )
    end

    for {mode, kind} <- [raise: :error, throw: :throw, exit: :exit] do
      assert {:error,
              {:indeterminate,
               %Jido.Error.ExecutionError{
                 details: %{code: :persistence_callback_failed, kind: ^kind}
               }}} =
               Persistence.save_agent({CASFaultAdapter, mode: mode}, agent, namespace: "persistence-test")
    end
  end

  test "writes every successful commit and preserves the Server revision" do
    persistence = adapter(:commit)
    jido = persistent_instance(persistence)
    id = unique_id("commit")

    {:ok, pid} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, RuntimeAgent,
        id: id,
        persistence_mode: :create
      )

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(pid, Signal.new!("runtime.record", %{event: :saved}, source: "/test"))

    agent = Server.snapshot(pid).agent
    assert agent.state.events == [:saved]

    assert {:ok, restored, 2} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, id, instance: jido)

    assert restored.state.events == [:saved]
  end

  test "stop persists and stops an idle Agent Server" do
    persistence = adapter(:hibernate)
    jido = persistent_instance(persistence)
    id = unique_id("hibernate")

    {:ok, pid} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, RuntimeAgent,
        id: id,
        persistence_mode: :create
      )

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(pid, Signal.new!("runtime.record", %{event: :saved}, source: "/test"))

    monitor = Process.monitor(pid)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :shutdown}, 1_000

    assert {:ok, restored} =
             Persistence.load_agent(persistence, RuntimeAgent, id, instance: jido)

    assert restored.state.events == [:saved]
  end

  test "a persistence conflict removes the stale Server's write authority" do
    persistence = adapter(:stale_server)
    jido = persistent_instance(persistence)
    agent = RuntimeAgent.instantiate!(id: unique_id("stale-server"))

    opts = [
      persistence_mode: :create,
      default_dispatch: {:pid, target: self()}
    ]

    assert {:ok, stale} = Jido.Test.AgentServer.Assertions.start_agent(jido, agent, opts)
    monitor = Process.monitor(stale)
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
        %{event: :stale, directive: Jido.Agent.Directive.emit(output)},
        source: "/test"
      )

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :uncertain,
              durability: :unknown,
              error: :conflict,
              effects: :none
            }} =
             Server.call(stale, command)

    refute_received {:signal, ^output}
    assert Process.alive?(stale)
    assert Server.status(stale).work_state == :faulted
    assert Server.status(stale).admission == :blocked
    refute_receive {:DOWN, ^monitor, :process, ^stale, _reason}, 20

    assert {:ok, ^committed, 1} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id, instance: jido)
  end

  test "thaw restores, starts, and rebuilds Plugin runtimes" do
    persistence = adapter(:thaw)
    jido = persistent_instance(persistence)
    id = unique_id("thaw")
    agent = RuntimeAgent.instantiate!(id: id, state: %{events: [:saved], ticks: 2})

    assert :ok =
             Persistence.save_agent(persistence, agent,
               instance: jido,
               revision: 7,
               reason: :hibernate
             )

    assert {:ok, pid} = Jido.thaw(jido, RuntimeAgent, id)

    assert :ok = Server.await_ready(pid)
    assert Server.snapshot(pid).agent.state.events == [:saved]
    assert %{state_version: 7} = Jido.Test.AgentServer.Assertions.committed(pid)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(pid, Signal.new!("runtime.record", %{event: :next}, source: "/test"))

    assert {:ok, _restored, 9} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, id, instance: jido)
  end

  test "explicit restore loads an existing record" do
    persistence = adapter(:automatic_restore)
    jido = persistent_instance(persistence)
    id = unique_id("automatic-restore")
    agent = RestoreAgent.instantiate!(id: id, state: %{create: true})

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido, revision: 3)

    assert {:ok, pid} =
             Jido.Test.AgentServer.Assertions.start_agent(jido, RestoreAgent,
               id: id,
               persistence_mode: :restore
             )

    assert Server.snapshot(pid).agent == agent
    assert %{state_version: 3} = Jido.Test.AgentServer.Assertions.committed(pid)
  end

  test "deletes one persisted Agent", %{jido: jido} do
    persistence = adapter(:delete)
    agent = RuntimeAgent.instantiate!(id: unique_id("delete"))

    assert :ok = Persistence.save_agent(persistence, agent, instance: jido)
    assert :ok = Persistence.delete_agent(persistence, RuntimeAgent, agent.id, instance: jido)

    assert {:error, :deleted} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id, instance: jido)
  end

  test "rejects an invalid persistence record" do
    {ETS, opts} = persistence = adapter(:invalid_record)
    agent = RuntimeAgent.instantiate!(id: unique_id("invalid-record"))
    key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-test", id: agent.id))

    assert :ok = ETS.put(key, <<0, 1, 2>>, opts)

    assert {:error, :invalid_persistence_record} =
             Persistence.load_agent(persistence, RuntimeAgent, agent.id, namespace: "persistence-test")

    assert {:error, :invalid_persistence_record} =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 1
             )

    assert {:ok, <<0, 1, 2>>} = ETS.get(key, opts)
  end

  test "rejects stale revisions and different state at the same revision" do
    persistence = adapter(:revisions)
    agent = RuntimeAgent.instantiate!(id: unique_id("revisions"), state: %{events: [:saved]})
    changed = %{agent | state: %{agent.state | events: [:changed]}}

    assert :ok =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 2
             )

    assert :ok =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 2,
               expected_revision: 2
             )

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 2,
               expected_revision: 1
             )

    for revision <- [0, 1, 2] do
      assert {:error, :conflict} =
               Persistence.save_agent(persistence, changed,
                 namespace: "persistence-test",
                 revision: revision
               )
    end

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, changed,
               namespace: "persistence-test",
               revision: 3,
               expected_revision: 1
             )

    assert {:ok, ^agent, 2} =
             Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id, namespace: "persistence-test")

    assert :ok =
             Persistence.save_agent(persistence, changed,
               namespace: "persistence-test",
               revision: 3,
               expected_revision: 2
             )
  end

  test "requires the expected record and validates the expected revision" do
    persistence = adapter(:expected)
    agent = RuntimeAgent.instantiate!(id: unique_id("expected"))

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 2,
               expected_revision: 1
             )

    for invalid <- [-1, nil, "0"] do
      assert {:error, {:invalid_expected_revision, ^invalid}} =
               Persistence.save_agent(persistence, agent,
                 namespace: "persistence-test",
                 expected_revision: invalid
               )
    end

    assert :ok =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 1,
               expected_revision: 0
             )

    assert :ok =
             Persistence.delete_agent(persistence, RuntimeAgent, agent.id, namespace: "persistence-test")

    assert {:error, :conflict} =
             Persistence.save_agent(persistence, agent,
               namespace: "persistence-test",
               revision: 2,
               expected_revision: 1
             )
  end

  test "only one writer commits when both read the same durable value" do
    for initial_revision <- [0, 1] do
      {ETS, opts} = persistence = adapter(:race)
      agent = RuntimeAgent.instantiate!(id: unique_id("race"))

      if initial_revision == 1 do
        assert :ok =
                 Persistence.save_agent(persistence, agent,
                   namespace: "persistence-test",
                   revision: 1
                 )
      end

      guarded = {BarrierAdapter, Keyword.put(opts, :observer, self())}

      tasks =
        for event <- [:first, :second] do
          candidate = %{agent | state: %{agent.state | events: [event]}}

          Task.async(fn ->
            result =
              Persistence.save_agent(guarded, candidate,
                namespace: "persistence-test",
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
               Persistence.load_agent_with_revision(persistence, RuntimeAgent, agent.id, namespace: "persistence-test")
    end
  end

  test "a live Server snapshot exposes no private process references", %{jido: jido} do
    {:ok, pid} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, RuntimeAgent, id: unique_id("snapshot"))

    assert %{agent: %Agent{}, state_version: 0} = Jido.Test.AgentServer.Assertions.committed(pid)

    snapshot = Jido.Test.AgentServer.Assertions.committed(pid)
    refute Map.has_key?(snapshot, :children)
    refute Map.has_key?(snapshot, :active)
    refute Map.has_key?(snapshot, :runtime)
  end
end
