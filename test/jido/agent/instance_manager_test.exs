defmodule JidoTest.Agent.InstanceManagerTest do
  use ExUnit.Case, async: false

  import JidoTest.Eventually

  # Tests with timing-based assertions (idle timeout behavior)
  @moduletag :integration

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Storage.ETS

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
