defmodule JidoTest.Agent.InstanceManagerTest do
  use ExUnit.Case, async: false

  import JidoTest.Eventually

  # Tests with timing-based assertions (idle timeout behavior)
  @moduletag :integration

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Storage.ETS, as: StorageETS

  # Use module attribute for manager naming to avoid atom leaks
  # Each test gets a unique integer suffix but we clean up persistent_term
  @manager_prefix "instance_manager_test"

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

  # Agent with custom dump/load
  defmodule CustomSerializeAgent do
    use Jido.Agent,
      name: "custom_serialize_agent",
      description: "Agent with custom serialization",
      schema: [
        data: [type: :map, default: %{}],
        runtime_pid: [type: :any, default: nil]
      ],
      actions: []

    def dump(agent, _ctx) do
      # Strip runtime-only fields
      {:ok, Map.drop(agent.state, [:runtime_pid])}
    end

    def load(dump, _ctx) do
      # Restore with defaults
      state = Map.put(dump, :runtime_pid, nil)
      agent = CustomSerializeAgent.new(state: state)
      {:ok, agent}
    end
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
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn -> :persistent_term.erase({InstanceManager, manager_name}) end)

      {:ok, manager: manager_name}
    end

    test "get/3 starts agent if not running", %{manager: manager} do
      assert InstanceManager.lookup(manager, "key-1") == {:error, :not_found}

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
  end

  describe "stop/2" do
    setup do
      manager_name = :"#{@manager_prefix}_stop_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
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
      eventually(fn -> InstanceManager.lookup(manager, "stop-key") == {:error, :not_found} end)
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
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
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
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
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

  describe "storage-backed hibernate/thaw" do
    setup do
      manager_name = :"#{@manager_prefix}_persist_#{:erlang.unique_integer([:positive])}"
      table_name = :"#{@manager_prefix}_cache_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_name,
            agent: TestAgent,
            idle_timeout: 200,
            storage: {Jido.Storage.ETS, table: table_name},
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          )
        )

      on_exit(fn ->
        :persistent_term.erase({InstanceManager, manager_name})

        :ok = StorageETS.cleanup(table: table_name)
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

      # Verify state was persisted to storage checkpoint.
      # Persistence may complete asynchronously during terminate.
      checkpoint_key = {Jido.Agent, "stop-persist-key"}

      assert {:ok, persisted} =
               eventually(
                 fn ->
                   case StorageETS.get_checkpoint(checkpoint_key, table: table) do
                     {:ok, checkpoint} -> {:ok, checkpoint}
                     {:error, :not_found} -> false
                   end
                 end,
                 timeout: 2_000
               )

      assert persisted.state.counter == 42
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
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
          ),
          id: :manager_a
        )

      {:ok, _} =
        start_supervised(
          InstanceManager.child_spec(
            name: manager_b,
            agent: TestAgent,
            agent_opts: [jido: JidoTest.InstanceManagerTestJido]
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

  describe "manager naming guards" do
    test "rejects non-atom manager names for generated process names" do
      assert_raise ArgumentError, ~r/manager must be an atom/i, fn ->
        InstanceManager.supervisor_name("sessions")
      end

      assert_raise ArgumentError, ~r/manager must be an atom/i, fn ->
        InstanceManager.registry_name("sessions")
      end

      assert_raise ArgumentError, ~r/manager must be an atom/i, fn ->
        InstanceManager.dynamic_supervisor_name("sessions")
      end
    end
  end
end
