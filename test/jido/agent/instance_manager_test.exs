defmodule JidoTest.Agent.InstanceManagerTest do
  use ExUnit.Case, async: false

  import JidoTest.Eventually

  # Tests with timing-based assertions (idle timeout behavior)
  @moduletag :integration

  alias Jido.Agent.InstanceManager
  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Scheduler
  alias Jido.Signal
  alias Jido.Storage.ETS
  alias Jido.Storage.Redis

  # Use module attribute for manager naming to avoid atom leaks
  # Each test gets a unique integer suffix but we clean up persistent_term
  @manager_prefix "instance_manager_test"

  defmodule StorageAwareJido do
    use Jido, otp_app: :jido_test_instance_manager

    def storage_table do
      {_adapter, opts} = __jido_storage__()
      Keyword.get(opts, :table, :jido_storage)
    end
  end

  defmodule RedisMock do
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [opts]}
      }
    end

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def command(command) do
      Agent.get_and_update(__MODULE__, fn state ->
        case command do
          ["GET", key] ->
            {{:ok, Map.get(state, key)}, state}

          ["SET", key, value] ->
            {{:ok, "OK"}, Map.put(state, key, value)}

          ["SET", key, value, "PX", _ttl] ->
            {{:ok, "OK"}, Map.put(state, key, value)}

          ["DEL" | keys] ->
            deleted = Enum.count(keys, &Map.has_key?(state, &1))
            {{:ok, deleted}, Map.drop(state, keys)}

          _ ->
            {{:error, :unknown_command}, state}
        end
      end)
    end

    def data do
      Agent.get(__MODULE__, & &1)
    end
  end

  defmodule RedisStorageAwareJido do
    use Jido,
      otp_app: :jido_test_instance_manager,
      storage:
        {Redis,
         [
           command_fn: fn cmd -> JidoTest.Agent.InstanceManagerTest.RedisMock.command(cmd) end,
           prefix: "instance_manager_test"
         ]}
  end

  # Simple test agent
  defmodule TestAgent do
    use Jido.Agent,
      name: "test_agent",
      description: "Test agent for instance manager tests",
      schema: [
        counter: [type: :integer, default: 0]
      ],
      actions: []
  end

  defmodule CronTickAction do
    @moduledoc false
    use Jido.Action, name: "cron_tick", schema: []

    @impl true
    def run(_params, context) do
      count = Map.get(context.state, :tick_count, 0)
      {:ok, %{tick_count: count + 1}}
    end
  end

  defmodule RegisterCronAction do
    @moduledoc false
    use Jido.Action, name: "register_cron", schema: []

    @impl true
    def run(params, _context) do
      cron = Map.get(params, :cron, "* * * * * * *")
      job_id = Map.get(params, :job_id, :durable_tick)
      timezone = Map.get(params, :timezone)
      message = Signal.new!("cron.tick", %{}, source: "/instance-manager-test")

      {:ok, %{}, [Directive.cron(cron, message, job_id: job_id, timezone: timezone)]}
    end
  end

  defmodule CancelCronAction do
    @moduledoc false
    use Jido.Action, name: "cancel_cron", schema: []

    @impl true
    def run(%{job_id: job_id}, _context) do
      {:ok, %{}, [Directive.cron_cancel(job_id)]}
    end
  end

  defmodule DurableCronAgent do
    @moduledoc false
    use Jido.Agent,
      name: "durable_cron_agent",
      schema: [
        tick_count: [type: :integer, default: 0]
      ]

    @impl true
    def signal_routes(_ctx) do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", CronTickAction}
      ]
    end
  end

  defmodule DeclarativeConflictAgent do
    @moduledoc false
    use Jido.Agent,
      name: "declarative_conflict_agent",
      schema: [
        tick_count: [type: :integer, default: 0]
      ],
      schedules: [
        {"* * * * *", "cron.tick", job_id: :declarative_conflict}
      ]

    @impl true
    def signal_routes(_ctx) do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", CronTickAction}
      ]
    end
  end

  defp cleanup_storage_tables(table) do
    Enum.each([:"#{table}_checkpoints", :"#{table}_threads", :"#{table}_thread_meta"], fn t ->
      try do
        :ets.delete(t)
      rescue
        _ -> :ok
      end
    end)
  end

  setup do
    # Start Jido instance for tests
    {:ok, _} = start_supervised({Jido, name: JidoTest.InstanceManagerTestJido})
    :ok
  end

  describe "child_spec/1" do
    test "creates valid supervisor child spec" do
      spec = InstanceManager.child_spec(name: :test_manager, agent: TestAgent)

      assert spec.id == {InstanceManager, :test_manager}
      assert spec.type == :supervisor
    end
  end

  describe "get/3 and lookup/2" do
    setup do
      manager_name = :"#{@manager_prefix}_get_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    test "get/3 starts agent if not running", %{manager: manager} do
      assert InstanceManager.lookup(manager, "key-1") == :error

      {:ok, pid} = InstanceManager.get(manager, "key-1")
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Lookup should now find it
      assert InstanceManager.lookup(manager, "key-1") == {:ok, pid}
    end

    test "get/3 returns same pid for same key", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "key-2")
      {:ok, pid2} = InstanceManager.get(manager, "key-2")

      assert pid1 == pid2
    end

    test "get/3 returns different pids for different keys", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "key-a")
      {:ok, pid2} = InstanceManager.get(manager, "key-b")

      assert pid1 != pid2
    end

    test "get/3 passes initial_state", %{manager: manager} do
      {:ok, pid} = InstanceManager.get(manager, "key-state", initial_state: %{counter: 42})
      {:ok, state} = AgentServer.state(pid)

      assert state.agent.state.counter == 42
    end

    test "manager-managed agents are not globally registered in Jido registry", %{
      manager: manager
    } do
      {:ok, pid} = InstanceManager.get(manager, "registry-scope-key")

      assert InstanceManager.lookup(manager, "registry-scope-key") == {:ok, pid}
      assert Jido.whereis(JidoTest.InstanceManagerTestJido, "registry-scope-key") == nil
    end

    test "get/3 and lookup/3 isolate same manager key across partitions", %{manager: manager} do
      {:ok, alpha_pid} = InstanceManager.get(manager, "shared-key", partition: :alpha)
      {:ok, beta_pid} = InstanceManager.get(manager, "shared-key", partition: :beta)

      assert alpha_pid != beta_pid
      assert InstanceManager.lookup(manager, "shared-key", partition: :alpha) == {:ok, alpha_pid}
      assert InstanceManager.lookup(manager, "shared-key", partition: :beta) == {:ok, beta_pid}
      assert InstanceManager.lookup(manager, "shared-key") == :error
    end
  end

  describe "agent_module/1" do
    setup do
      manager_name = :"#{@manager_prefix}_agent_module_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    test "returns the configured agent module", %{manager: manager} do
      assert InstanceManager.agent_module(manager) == {:ok, TestAgent}
    end

    test "returns :not_found for an unknown manager" do
      assert InstanceManager.agent_module(:missing_manager_for_agent_module) == {:error, :not_found}
    end
  end

  describe "stop/2" do
    setup do
      manager_name = :"#{@manager_prefix}_stop_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    test "stop/2 terminates agent", %{manager: manager} do
      {:ok, pid} = InstanceManager.get(manager, "stop-key")
      assert Process.alive?(pid)

      # Monitor the process to detect termination
      ref = Process.monitor(pid)

      :ok = InstanceManager.stop(manager, "stop-key")

      # Wait for DOWN message instead of sleep
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

      # Lookup should return error
      assert InstanceManager.lookup(manager, "stop-key") == :error
    end

    test "stop/2 returns error for non-existent key", %{manager: manager} do
      assert InstanceManager.stop(manager, "nonexistent") == {:error, :not_found}
    end
  end

  describe "attach/detach" do
    setup do
      manager_name = :"#{@manager_prefix}_attach_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    @tag timeout: 5000
    test "attach prevents idle timeout, detach allows it", %{manager: manager} do
      {:ok, pid} = InstanceManager.get(manager, "attach-key")
      ref = Process.monitor(pid)
      :ok = AgentServer.attach(pid)

      # Should not receive DOWN while attached (wait longer than idle_timeout)
      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 300

      # Detach and wait for idle timeout to stop the process
      :ok = AgentServer.detach(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :idle_timeout}}, 1000
    end

    @tag timeout: 5000
    test "attach monitors caller and auto-detaches on exit", %{manager: manager} do
      {:ok, pid} = InstanceManager.get(manager, "monitor-key")
      ref = Process.monitor(pid)

      # Spawn a process that attaches then exits
      test_pid = self()

      owner =
        spawn(fn ->
          :ok = AgentServer.attach(pid)
          send(test_pid, :attached)
          # Process exits here
        end)

      # Wait for attachment
      assert_receive :attached, 1000

      # Owner has exited, wait for agent to idle timeout
      refute Process.alive?(owner)
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :idle_timeout}}, 1000
    end

    @tag timeout: 5000
    test "touch resets idle timer", %{manager: manager} do
      {:ok, pid} = InstanceManager.get(manager, "touch-key")
      ref = Process.monitor(pid)

      # Touch a few times, each within idle timeout window
      for _ <- 1..3 do
        :ok = AgentServer.touch(pid)
        refute_receive {:DOWN, ^ref, :process, ^pid, _}, 100
      end

      # Stop touching and wait for timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :idle_timeout}}, 1000
    end
  end

  describe "stats/1" do
    setup do
      manager_name = :"#{@manager_prefix}_stats_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    test "stats returns count and keys", %{manager: manager} do
      InstanceManager.get(manager, "key-1")
      InstanceManager.get(manager, "key-2")
      InstanceManager.get(manager, "key-3")

      stats = InstanceManager.stats(manager)

      assert stats.count == 3
      assert "key-1" in stats.keys
      assert "key-2" in stats.keys
      assert "key-3" in stats.keys
    end
  end

  describe "storage with ETS adapter" do
    setup do
      manager_name = :"#{@manager_prefix}_persist_#{:erlang.unique_integer([:positive])}"
      table_name = :"#{@manager_prefix}_cache_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            storage: {ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})
        cleanup_storage_tables(table_name)
      end)

      {:ok, manager: manager_name, table: table_name}
    end

    @tag timeout: 5000
    test "agent hibernates on idle timeout and thaws on get", %{manager: manager} do
      # Start agent with initial state
      {:ok, pid1} = InstanceManager.get(manager, "hibernate-key", initial_state: %{counter: 99})
      ref = Process.monitor(pid1)
      {:ok, state1} = AgentServer.state(pid1)
      assert state1.agent.state.counter == 99

      # Wait for idle timeout to hibernate
      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 1000

      # Verify the old process is truly dead
      refute Process.alive?(pid1)

      # Get should thaw the agent with persisted state (new process)
      # Use eventually to handle race where agent may hibernate before attach
      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "hibernate-key")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 2000
        )

      assert Process.alive?(pid2)

      {:ok, state2} = AgentServer.state(pid2)
      # The important assertion: state was preserved
      assert state2.agent.state.counter == 99

      # Cleanup
      :ok = AgentServer.detach(pid2)
    end

    @tag timeout: 5000
    test "stop/2 hibernates agent before terminating", %{manager: manager, table: table} do
      # Start agent with initial state
      {:ok, pid} = InstanceManager.get(manager, "stop-persist-key", initial_state: %{counter: 42})
      ref = Process.monitor(pid)
      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 42

      # Stop the agent (should hibernate first)
      :ok = InstanceManager.stop(manager, "stop-persist-key")

      # Wait for process to terminate
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

      # Verify state was persisted to ETS
      store_key = {TestAgent, {manager, "stop-persist-key"}}

      case ETS.get_checkpoint(store_key, table: table) do
        {:ok, persisted} ->
          # Persisted data should contain the counter
          assert persisted.state.counter == 42

        :not_found ->
          flunk("Agent state was not persisted on stop")
      end
    end

    @tag timeout: 5000
    test "partitioned storage keeps same manager key isolated across partitions", %{
      manager: manager,
      table: table
    } do
      {:ok, alpha_pid} =
        InstanceManager.get(manager, "shared-storage-key",
          partition: :alpha,
          initial_state: %{counter: 11}
        )

      {:ok, beta_pid} =
        InstanceManager.get(manager, "shared-storage-key",
          partition: :beta,
          initial_state: %{counter: 22}
        )

      alpha_ref = Process.monitor(alpha_pid)
      beta_ref = Process.monitor(beta_pid)

      :ok = InstanceManager.stop(manager, "shared-storage-key", partition: :alpha)
      :ok = InstanceManager.stop(manager, "shared-storage-key", partition: :beta)

      assert_receive {:DOWN, ^alpha_ref, :process, ^alpha_pid, _reason}, 1000
      assert_receive {:DOWN, ^beta_ref, :process, ^beta_pid, _reason}, 1000

      assert {:ok, alpha_checkpoint} =
               ETS.get_checkpoint(
                 {TestAgent, {:partition, :alpha, {manager, "shared-storage-key"}}},
                 table: table
               )

      assert {:ok, beta_checkpoint} =
               ETS.get_checkpoint(
                 {TestAgent, {:partition, :beta, {manager, "shared-storage-key"}}},
                 table: table
               )

      assert alpha_checkpoint.state.counter == 11
      assert beta_checkpoint.state.counter == 22

      {:ok, restored_alpha} =
        InstanceManager.get(manager, "shared-storage-key", partition: :alpha)

      {:ok, restored_beta} = InstanceManager.get(manager, "shared-storage-key", partition: :beta)

      {:ok, alpha_state} = AgentServer.state(restored_alpha)
      {:ok, beta_state} = AgentServer.state(restored_beta)

      assert alpha_state.partition == :alpha
      assert alpha_state.agent.state.counter == 11
      assert alpha_state.agent.state.__partition__ == :alpha

      assert beta_state.partition == :beta
      assert beta_state.agent.state.counter == 22
      assert beta_state.agent.state.__partition__ == :beta
    end
  end

  describe "default storage from jido instance" do
    setup do
      manager_name = :"#{@manager_prefix}_jido_default_#{:erlang.unique_integer([:positive])}"

      {:ok, _} = start_supervised(StorageAwareJido)

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            agent_opts: [jido: StorageAwareJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})
        cleanup_storage_tables(StorageAwareJido.storage_table())
      end)

      {:ok, manager: manager_name}
    end

    @tag timeout: 5000
    test "omitted storage uses jido instance storage", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "jido-default", initial_state: %{counter: 123})
      ref = Process.monitor(pid1)

      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 1000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "jido-default")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 2000
        )

      {:ok, state2} = AgentServer.state(pid2)
      assert state2.agent.state.counter == 123

      :ok = AgentServer.detach(pid2)
    end
  end

  describe "default storage from redis-backed jido instance" do
    setup do
      manager_name = :"#{@manager_prefix}_redis_default_#{:erlang.unique_integer([:positive])}"

      {:ok, _} = start_supervised({RedisMock, []})
      {:ok, _} = start_supervised(RedisStorageAwareJido)

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            agent_opts: [jido: RedisStorageAwareJido]
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    @tag timeout: 5000
    test "omitted storage uses redis storage from the jido instance", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "redis-default", initial_state: %{counter: 123})
      ref = Process.monitor(pid1)

      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 1000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "redis-default")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 2000
        )

      {:ok, state2} = AgentServer.state(pid2)
      assert state2.agent.state.counter == 123
      assert map_size(RedisMock.data()) > 0

      :ok = AgentServer.detach(pid2)
    end
  end

  describe "durable cron persistence with InstanceManager storage" do
    setup do
      manager_name = :"#{@manager_prefix}_durable_cron_#{:erlang.unique_integer([:positive])}"
      table_name = :"#{@manager_prefix}_durable_cron_table_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: DurableCronAgent,
            idle_timeout: 200,
            storage: {ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})
        cleanup_storage_tables(table_name)
      end)

      {:ok, manager: manager_name, table: table_name}
    end

    @tag timeout: 8_000
    test "dynamic cron registrations survive hibernate/thaw", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "durable-cron-1")
      :ok = AgentServer.attach(pid1)

      register_signal =
        Signal.new!("register_cron", %{job_id: :durable_tick, cron: "* * * * * * *"},
          source: "/test"
        )

      :ok = AgentServer.cast(pid1, register_signal)

      _state1 =
        eventually_state(
          pid1,
          fn state ->
            Map.has_key?(state.cron_jobs, :durable_tick) and
              Map.has_key?(state.cron_specs, :durable_tick)
          end,
          timeout: 2_000
        )

      state1 =
        eventually_state(pid1, fn state -> state.agent.state.tick_count > 0 end, timeout: 3_000)

      pre_hibernate_ticks = state1.agent.state.tick_count

      :ok = AgentServer.detach(pid1)
      ref = Process.monitor(pid1)
      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 2_000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "durable-cron-1")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 3_000
        )

      refute pid1 == pid2

      eventually_state(pid2, fn state -> Map.has_key?(state.cron_jobs, :durable_tick) end,
        timeout: 2_000
      )

      eventually_state(
        pid2,
        fn state ->
          state.agent.state.tick_count > pre_hibernate_ticks
        end,
        timeout: 3_000
      )

      :ok = AgentServer.detach(pid2)
    end

    @tag timeout: 8_000
    test "cancelled dynamic cron does not re-register after thaw", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "durable-cron-2")
      :ok = AgentServer.attach(pid1)

      register_signal =
        Signal.new!("register_cron", %{job_id: :to_cancel, cron: "* * * * * * *"},
          source: "/test"
        )

      cancel_signal =
        Signal.new!("cancel_cron", %{job_id: :to_cancel}, source: "/test")

      :ok = AgentServer.cast(pid1, register_signal)

      eventually_state(pid1, fn state -> Map.has_key?(state.cron_jobs, :to_cancel) end,
        timeout: 2_000
      )

      :ok = AgentServer.cast(pid1, cancel_signal)

      eventually_state(
        pid1,
        fn state ->
          not Map.has_key?(state.cron_jobs, :to_cancel) and
            not Map.has_key?(state.cron_specs, :to_cancel)
        end,
        timeout: 2_000
      )

      :ok = AgentServer.detach(pid1)
      ref = Process.monitor(pid1)
      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 2_000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "durable-cron-2")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 3_000
        )

      {:ok, state2} = AgentServer.state(pid2)
      assert map_size(state2.cron_jobs) == 0
      assert map_size(state2.cron_specs) == 0

      :ok = AgentServer.detach(pid2)
    end

    @tag timeout: 8_000
    test "write-through register survives abrupt process loss", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "durable-cron-kill-register")
      :ok = AgentServer.attach(pid1)

      register_signal =
        Signal.new!("register_cron", %{job_id: :after_kill_register, cron: "* * * * * * *"},
          source: "/test"
        )

      :ok = AgentServer.cast(pid1, register_signal)

      eventually_state(
        pid1,
        fn state ->
          Map.has_key?(state.cron_jobs, :after_kill_register) and
            Map.has_key?(state.cron_specs, :after_kill_register)
        end,
        timeout: 2_000
      )

      ref = Process.monitor(pid1)
      Process.exit(pid1, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid1, :killed}, 2_000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "durable-cron-kill-register")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 3_000
        )

      state2 =
        eventually_state(
          pid2,
          fn state ->
            Map.has_key?(state.cron_jobs, :after_kill_register) and
              Map.has_key?(state.cron_specs, :after_kill_register)
          end,
          timeout: 3_000
        )

      assert is_pid(state2.cron_jobs[:after_kill_register])
      :ok = AgentServer.detach(pid2)
    end

    @tag timeout: 8_000
    test "write-through cancel survives abrupt process loss", %{manager: manager} do
      {:ok, pid1} = InstanceManager.get(manager, "durable-cron-kill-cancel")
      :ok = AgentServer.attach(pid1)

      register_signal =
        Signal.new!("register_cron", %{job_id: :after_kill_cancel, cron: "* * * * * * *"},
          source: "/test"
        )

      cancel_signal =
        Signal.new!("cancel_cron", %{job_id: :after_kill_cancel}, source: "/test")

      :ok = AgentServer.cast(pid1, register_signal)

      eventually_state(
        pid1,
        fn state ->
          Map.has_key?(state.cron_jobs, :after_kill_cancel) and
            Map.has_key?(state.cron_specs, :after_kill_cancel)
        end,
        timeout: 2_000
      )

      :ok = AgentServer.cast(pid1, cancel_signal)

      eventually_state(
        pid1,
        fn state ->
          not Map.has_key?(state.cron_jobs, :after_kill_cancel) and
            not Map.has_key?(state.cron_specs, :after_kill_cancel)
        end,
        timeout: 2_000
      )

      ref = Process.monitor(pid1)
      Process.exit(pid1, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid1, :killed}, 2_000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, "durable-cron-kill-cancel")

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 3_000
        )

      {:ok, state2} = AgentServer.state(pid2)
      refute Map.has_key?(state2.cron_jobs, :after_kill_cancel)
      refute Map.has_key?(state2.cron_specs, :after_kill_cancel)

      :ok = AgentServer.detach(pid2)
    end
  end

  describe "restored cron conflict policy with declarative schedules" do
    setup do
      manager_name =
        :"#{@manager_prefix}_durable_cron_conflict_#{:erlang.unique_integer([:positive])}"

      table_name =
        :"#{@manager_prefix}_durable_cron_conflict_table_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: DeclarativeConflictAgent,
            idle_timeout: 200,
            storage: {ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})
        cleanup_storage_tables(table_name)
      end)

      {:ok, manager: manager_name, table: table_name}
    end

    @tag timeout: 8_000
    test "declarative schedule wins over restored dynamic conflict and persisted manifest is cleaned",
         %{
           manager: manager,
           table: table
         } do
      conflict_job_id = {:agent_schedule, "declarative_conflict_agent", :declarative_conflict}
      instance_key = "durable-cron-conflict-1"

      {:ok, pid1} = InstanceManager.get(manager, instance_key)
      :ok = AgentServer.attach(pid1)

      eventually_state(pid1, fn state -> Map.has_key?(state.cron_jobs, conflict_job_id) end,
        timeout: 2_000
      )

      register_signal =
        Signal.new!("register_cron", %{job_id: conflict_job_id, cron: "@hourly"}, source: "/test")

      :ok = AgentServer.cast(pid1, register_signal)

      eventually_state(
        pid1,
        fn state ->
          Map.has_key?(state.cron_jobs, conflict_job_id) and
            Map.has_key?(state.cron_specs, conflict_job_id)
        end,
        timeout: 2_000
      )

      ref = Process.monitor(pid1)
      Process.exit(pid1, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid1, :killed}, 2_000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager, instance_key)

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 3_000
        )

      state2 =
        eventually_state(
          pid2,
          fn state ->
            Map.has_key?(state.cron_jobs, conflict_job_id) and
              not Map.has_key?(state.cron_specs, conflict_job_id)
          end,
          timeout: 3_000
        )

      assert is_pid(state2.cron_jobs[conflict_job_id])

      store_key = {DeclarativeConflictAgent, {manager, instance_key}}
      scheduler_key = Scheduler.cron_specs_state_key()

      eventually(
        fn ->
          case ETS.get_checkpoint(store_key, table: table) do
            {:ok, checkpoint} ->
              persisted_specs =
                checkpoint
                |> Map.get(:state, %{})
                |> Map.get(scheduler_key, %{})

              not Map.has_key?(persisted_specs, conflict_job_id)

            :not_found ->
              false
          end
        end,
        timeout: 3_000
      )

      :ok = AgentServer.detach(pid2)
    end
  end

  describe "storage controls" do
    test "legacy :persistence option raises actionable error" do
      manager_name =
        :"#{@manager_prefix}_legacy_persistence_#{:erlang.unique_integer([:positive])}"

      assert_raise RuntimeError, ~r/no longer supports :persistence; use :storage/, fn ->
        start_supervised!(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            persistence: {ETS, table: :legacy_persistence_should_fail},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )
      end
    end

    test "storage: nil disables restore" do
      manager_name = :"#{@manager_prefix}_no_storage_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            storage: nil,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, pid1} = InstanceManager.get(manager_name, "no-storage", initial_state: %{counter: 77})
      ref = Process.monitor(pid1)
      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 1000

      {:ok, pid2} = InstanceManager.get(manager_name, "no-storage")
      {:ok, state2} = AgentServer.state(pid2)
      assert state2.agent.state.counter == 0
    end

    test "explicit storage overrides jido default storage" do
      manager_name = :"#{@manager_prefix}_override_#{:erlang.unique_integer([:positive])}"
      override_table = :"#{@manager_prefix}_override_table_#{:erlang.unique_integer([:positive])}"

      {:ok, _} = start_supervised(StorageAwareJido)

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            storage: {ETS, table: override_table},
            agent_opts: [jido: StorageAwareJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})
        cleanup_storage_tables(override_table)
        cleanup_storage_tables(StorageAwareJido.storage_table())
      end)

      {:ok, _pid} =
        InstanceManager.get(manager_name, "override-key", initial_state: %{counter: 41})

      :ok = InstanceManager.stop(manager_name, "override-key")

      store_key = {TestAgent, {manager_name, "override-key"}}

      assert {:ok, _} = ETS.get_checkpoint(store_key, table: override_table)
      assert :not_found = ETS.get_checkpoint(store_key, table: StorageAwareJido.storage_table())
    end

    @tag timeout: 5000
    test "non-binary pool key round-trips persisted state" do
      manager_name = :"#{@manager_prefix}_tuple_key_#{:erlang.unique_integer([:positive])}"
      table_name = :"#{@manager_prefix}_tuple_table_#{:erlang.unique_integer([:positive])}"
      pool_key = {:user, 42}

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            storage: {ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})
        cleanup_storage_tables(table_name)
      end)

      {:ok, pid1} = InstanceManager.get(manager_name, pool_key, initial_state: %{counter: 55})
      ref = Process.monitor(pid1)
      assert_receive {:DOWN, ^ref, :process, ^pid1, {:shutdown, :idle_timeout}}, 1000

      {:ok, pid2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager_name, pool_key)

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 2000
        )

      {:ok, state2} = AgentServer.state(pid2)
      assert state2.agent.state.counter == 55
      assert String.starts_with?(state2.agent.id, "key_")

      :ok = AgentServer.detach(pid2)
    end

    @tag timeout: 5000
    test "manager name namespaces persistence keys to prevent cross-manager collisions" do
      table_name = :"#{@manager_prefix}_shared_table_#{:erlang.unique_integer([:positive])}"
      manager_a = :"#{@manager_prefix}_ns_a_#{:erlang.unique_integer([:positive])}"
      manager_b = :"#{@manager_prefix}_ns_b_#{:erlang.unique_integer([:positive])}"
      shared_key = "shared-user-key"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_a,
            agent: TestAgent,
            idle_timeout: 200,
            storage: {ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          ),
          id: :namespaced_manager_a
        )

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_b,
            agent: TestAgent,
            idle_timeout: 200,
            storage: {ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          ),
          id: :namespaced_manager_b
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_a})
        :persistent_term.erase({InstanceManager, manager_b})
        cleanup_storage_tables(table_name)
      end)

      {:ok, pid_a1} = InstanceManager.get(manager_a, shared_key, initial_state: %{counter: 11})
      {:ok, pid_b1} = InstanceManager.get(manager_b, shared_key, initial_state: %{counter: 22})

      ref_a = Process.monitor(pid_a1)
      ref_b = Process.monitor(pid_b1)

      assert_receive {:DOWN, ^ref_a, :process, ^pid_a1, {:shutdown, :idle_timeout}}, 1000
      assert_receive {:DOWN, ^ref_b, :process, ^pid_b1, {:shutdown, :idle_timeout}}, 1000

      {:ok, _checkpoint_a} =
        ETS.get_checkpoint({TestAgent, {manager_a, shared_key}}, table: table_name)

      {:ok, _checkpoint_b} =
        ETS.get_checkpoint({TestAgent, {manager_b, shared_key}}, table: table_name)

      {:ok, pid_a2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager_a, shared_key)

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 2000
        )

      {:ok, pid_b2} =
        eventually(
          fn ->
            {:ok, pid} = InstanceManager.get(manager_b, shared_key)

            case AgentServer.attach(pid) do
              :ok -> {:ok, pid}
              _ -> false
            end
          end,
          timeout: 2000
        )

      {:ok, state_a2} = AgentServer.state(pid_a2)
      {:ok, state_b2} = AgentServer.state(pid_b2)

      assert state_a2.agent.state.counter == 11
      assert state_b2.agent.state.counter == 22

      :ok = AgentServer.detach(pid_a2)
      :ok = AgentServer.detach(pid_b2)
    end
  end

  describe "multiple managers" do
    setup do
      manager_a = :"#{@manager_prefix}_multi_a_#{:erlang.unique_integer([:positive])}"
      manager_b = :"#{@manager_prefix}_multi_b_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_a,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          ),
          id: :manager_a
        )

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_b,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido],
            storage: nil
          ),
          id: :manager_b
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_a})
        :persistent_term.erase({InstanceManager, manager_b})
      end)

      {:ok, manager_a: manager_a, manager_b: manager_b}
    end

    test "managers are independent", %{manager_a: manager_a, manager_b: manager_b} do
      {:ok, pid_a} = InstanceManager.get(manager_a, "shared-key")
      {:ok, pid_b} = InstanceManager.get(manager_b, "shared-key")

      assert pid_a != pid_b

      # Stats are separate
      assert InstanceManager.stats(manager_a).count == 1
      assert InstanceManager.stats(manager_b).count == 1
    end
  end
end
