defmodule Jido.Agent.LifecycleTest do
  use ExUnit.Case, async: true
  doctest Jido.Agent.Lifecycle

  import JidoTest.Support

  alias Jido.Agent.Lifecycle
  alias Jido.Agent.Server
  alias JidoTest.TestAgents.{BasicAgent, MinimalAgent}

  @moduletag :capture_log

  # ============================================================================
  # start_agent/2 tests - Core functionality
  # ============================================================================

  describe "start_agent/2 with agent struct" do
    test "starts agent with struct" do
      {:ok, registry} = start_registry!()
      agent = BasicAgent.new(unique_id("agent"))

      {:ok, pid} = Lifecycle.start_agent(agent, registry: registry)

      assert is_pid(pid)

      {:ok, state} = Server.state(pid)
      assert state.agent.id == agent.id
      assert state.agent.__struct__ == agent.__struct__
    end

    test "starts agent struct with options override" do
      {:ok, registry} = start_registry!()
      agent = BasicAgent.new(unique_id("agent"))

      {:ok, pid} =
        Lifecycle.start_agent(agent,
          registry: registry,
          log_level: :debug,
          max_queue_size: 5000
        )

      {:ok, state} = Server.state(pid)
      assert state.log_level == :debug
      assert state.max_queue_size == 5000
    end
  end

  describe "start_agent/2 with module" do
    test "starts agent with module and ID option" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("agent")

      {:ok, pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          registry: registry
        )

      assert is_pid(pid)

      {:ok, state} = Server.state(pid)
      assert state.agent.id == agent_id
      assert state.agent.__struct__ == BasicAgent
    end

    test "starts agent with module and generates ID when not provided" do
      {:ok, registry} = start_registry!()

      {:ok, pid} = Lifecycle.start_agent(BasicAgent, registry: registry)

      {:ok, state} = Server.state(pid)
      assert is_binary(state.agent.id)
      assert String.length(state.agent.id) > 0
    end

    test "starts agent with module and initial state" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("agent")
      initial_state = %{custom_field: "test_value", battery_level: 75}

      {:ok, pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          initial_state: initial_state,
          registry: registry
        )

      {:ok, state} = Server.state(pid)
      assert state.agent.state.custom_field == "test_value"
      assert state.agent.state.battery_level == 75
    end
  end

  # ============================================================================
  # start_agents/1 tests
  # ============================================================================

  describe "start_agents/1" do
    test "starts multiple agents from different spec formats" do
      {:ok, registry} = start_registry!()
      agent1 = BasicAgent.new("agent-1")

      specs = [
        {agent1},
        {MinimalAgent, [id: "agent-2", registry: registry]}
      ]

      {:ok, pids} = Lifecycle.start_agents(specs)

      assert length(pids) == 2
      assert Enum.all?(pids, &is_pid/1)
    end

    test "returns all started PIDs on success" do
      {:ok, registry} = start_registry!()

      specs = [
        {BasicAgent, [id: "agent-1", registry: registry]},
        {BasicAgent, [id: "agent-2", registry: registry]}
      ]

      {:ok, [pid1, pid2]} = Lifecycle.start_agents(specs)

      {:ok, state1} = Server.state(pid1)
      {:ok, state2} = Server.state(pid2)

      assert state1.agent.id == "agent-1"
      assert state2.agent.id == "agent-2"
    end
  end

  # ============================================================================
  # Agent lifecycle operations - Table-driven tests
  # ============================================================================

  describe "stop_agent/2" do
    # Parameterized test for different stop scenarios
    stop_scenarios = [
      {:pid, "stops agent by PID"},
      {:id, "stops agent by ID"},
      {:ok_tuple, "stops agent with {:ok, pid} tuple"}
    ]

    for {scenario, description} <- stop_scenarios do
      @tag :slow
      test description do
        {:ok, registry} = start_registry!()
        agent_id = unique_id("agent")

        {:ok, pid} =
          Lifecycle.start_agent(BasicAgent,
            id: agent_id,
            registry: registry
          )

        # Stop using different identifiers based on scenario
        stop_result =
          case unquote(scenario) do
            :pid -> Lifecycle.stop_agent(pid)
            :id -> Lifecycle.stop_agent(agent_id, registry: registry)
            :ok_tuple -> Lifecycle.stop_agent({:ok, pid})
          end

        assert stop_result == :ok

        Process.sleep(100)
        refute Process.alive?(pid)
      end
    end

    test "returns :ok for non-existent agent by ID" do
      {:ok, registry} = start_registry!()
      :ok = Lifecycle.stop_agent("non-existent", registry: registry)
    end
  end

  # ============================================================================
  # get_agent/2 & get_agent!/2 tests
  # ============================================================================

  describe "get_agent/2" do
    test "finds agent by string ID" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("agent")

      {:ok, started_pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          registry: registry
        )

      {:ok, found_pid} = Lifecycle.get_agent(agent_id, registry: registry)

      assert found_pid == started_pid
    end

    test "returns error for non-existent agent" do
      {:ok, registry} = start_registry!()
      {:error, :not_found} = Lifecycle.get_agent("non-existent", registry: registry)
    end
  end

  describe "get_agent!/2" do
    test "returns PID for existing agent" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("agent")

      {:ok, started_pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          registry: registry
        )

      found_pid = Lifecycle.get_agent!(agent_id, registry: registry)

      assert found_pid == started_pid
    end

    test "raises for non-existent agent" do
      {:ok, registry} = start_registry!()

      assert_raise RuntimeError, ~r/Agent not found: non-existent/, fn ->
        Lifecycle.get_agent!("non-existent", registry: registry)
      end
    end
  end

  # ============================================================================
  # Agent status and utility functions
  # ============================================================================

  describe "agent_alive?/1" do
    test "returns true for alive PID" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)

      assert Lifecycle.agent_alive?(pid) == true

      Agent.stop(pid)
    end

    @tag :slow
    test "returns false for dead PID" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)
      Agent.stop(pid)

      Process.sleep(50)

      assert Lifecycle.agent_alive?(pid) == false
    end

    test "returns false for non-existent agent by ID" do
      assert Lifecycle.agent_alive?("non-existent") == false
    end

    test "handles {:ok, pid} tuple" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)

      assert Lifecycle.agent_alive?({:ok, pid}) == true

      Agent.stop(pid)
    end
  end

  # Table-driven tests for agent state operations
  state_operations = [
    {:get_agent_state, "get_agent_state/1", :test_field},
    {:get_agent_status, "get_agent_status/1", nil},
    {:queue_size, "queue_size/1", nil}
  ]

  for {operation, description, test_field} <- state_operations do
    describe description do
      test "returns result for agent PID" do
        {:ok, context} =
          start_basic_agent!(
            initial_state: %{test_field: "test_value"},
            cleanup: false
          )

        result =
          case unquote(operation) do
            :get_agent_state -> Lifecycle.get_agent_state(context.pid)
            :get_agent_status -> Lifecycle.get_agent_status(context.pid)
            :queue_size -> Lifecycle.queue_size(context.pid)
          end

        case unquote(operation) do
          :get_agent_state ->
            {:ok, state} = result

            if unquote(test_field) do
              assert state.agent.state.test_field == "test_value"
            else
              assert state.agent.id == context.id
            end

          :get_agent_status ->
            {:ok, status} = result
            assert status in [:idle, :running, :paused, :error, :stopping]

          :queue_size ->
            {:ok, size} = result
            assert is_integer(size) and size >= 0
        end

        cleanup_agent(context)
      end

      test "returns result for {:ok, pid} tuple" do
        {:ok, context} = start_basic_agent!(cleanup: false)

        result =
          case unquote(operation) do
            :get_agent_state -> Lifecycle.get_agent_state({:ok, context.pid})
            :get_agent_status -> Lifecycle.get_agent_status({:ok, context.pid})
            :queue_size -> Lifecycle.queue_size({:ok, context.pid})
          end

        assert match?({:ok, _}, result)
        cleanup_agent(context)
      end

      test "returns error for non-existent agent" do
        result =
          case unquote(operation) do
            :get_agent_state -> Lifecycle.get_agent_state("non-existent")
            :get_agent_status -> Lifecycle.get_agent_status("non-existent")
            :queue_size -> Lifecycle.queue_size("non-existent")
          end

        assert result == {:error, :not_found}
      end
    end
  end

  describe "queue_size/1 - additional tests" do
    test "queue size starts at 0 for new agent" do
      {:ok, context} = start_basic_agent!(cleanup: false)

      {:ok, size} = Lifecycle.queue_size(context.pid)

      assert size == 0
      cleanup_agent(context)
    end
  end

  # ============================================================================
  # list_running_agents/1 tests
  # ============================================================================

  describe "list_running_agents/1" do
    test "returns empty map when no agents running" do
      {:ok, registry} = start_registry!()
      {:ok, agents} = Lifecycle.list_running_agents(registry: registry)

      assert agents == %{}
    end

    test "lists single running agent" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("agent")

      {:ok, pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          registry: registry
        )

      {:ok, agents} = Lifecycle.list_running_agents(registry: registry)

      assert map_size(agents) == 1
      assert agents[agent_id] == pid
    end

    test "lists multiple running agents" do
      {:ok, registry} = start_registry!()
      agent_count = 3
      agent_ids = for n <- 1..agent_count, do: "agent-#{n}-#{System.unique_integer()}"

      pids =
        for id <- agent_ids do
          {:ok, pid} = Lifecycle.start_agent(BasicAgent, id: id, registry: registry)
          pid
        end

      {:ok, agents} = Lifecycle.list_running_agents(registry: registry)

      assert map_size(agents) == agent_count

      for {id, pid} <- agents do
        assert id in agent_ids
        assert pid in pids
      end
    end

    test "uses default registry when not specified" do
      {:ok, agents} = Lifecycle.list_running_agents()

      assert is_map(agents)
    end
  end

  # ============================================================================
  # Integration tests
  # ============================================================================

  describe "basic lifecycle integration" do
    @tag :slow
    test "start, get, and stop agent workflow" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("lifecycle")

      # 1. Start agent
      {:ok, pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          registry: registry,
          initial_state: %{counter: 0}
        )

      # 2. Verify agent is accessible
      {:ok, found_pid} = Lifecycle.get_agent(agent_id, registry: registry)
      assert found_pid == pid
      assert Lifecycle.agent_alive?(found_pid) == true

      # 3. Check initial state
      {:ok, state} = Lifecycle.get_agent_state(found_pid)
      assert state.agent.state.counter == 0

      # 4. Check status and queue
      {:ok, status} = Lifecycle.get_agent_status(found_pid)
      assert is_atom(status)

      {:ok, queue_size} = Lifecycle.queue_size(found_pid)
      assert queue_size == 0

      # 5. List agents
      {:ok, agents} = Lifecycle.list_running_agents(registry: registry)
      assert agents[agent_id] == pid

      # 6. Stop agent
      :ok = Lifecycle.stop_agent(agent_id, registry: registry)

      Process.sleep(100)

      # 7. Verify stopped
      assert Lifecycle.agent_alive?(agent_id) == false

      {:ok, final_agents} = Lifecycle.list_running_agents(registry: registry)
      refute Map.has_key?(final_agents, agent_id)
    end
  end

  # ============================================================================
  # Edge cases and error handling
  # ============================================================================

  describe "error handling" do
    @tag :slow
    test "handles operations on stopped agents gracefully" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("stopped")

      {:ok, pid} =
        Lifecycle.start_agent(BasicAgent,
          id: agent_id,
          registry: registry
        )

      :ok = Lifecycle.stop_agent(pid)
      Process.sleep(100)

      # Operations should handle stopped agent gracefully
      {:error, :not_found} = Lifecycle.get_agent_state(agent_id)
      {:error, :not_found} = Lifecycle.get_agent_status(agent_id)
      {:error, :not_found} = Lifecycle.queue_size(agent_id)
      assert Lifecycle.agent_alive?(agent_id) == false

      # Stop should be idempotent
      :ok = Lifecycle.stop_agent(agent_id, registry: registry)
    end

    @tag :slow
    test "handles concurrent operations on same agent" do
      {:ok, context} = start_basic_agent!(cleanup: false)

      # Perform concurrent operations
      tasks = [
        Task.async(fn -> Lifecycle.get_agent_state(context.pid) end),
        Task.async(fn -> Lifecycle.get_agent_status(context.pid) end),
        Task.async(fn -> Lifecycle.queue_size(context.pid) end),
        Task.async(fn -> Lifecycle.agent_alive?(context.pid) end)
      ]

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               # agent_alive? returns boolean
               true -> true
               false -> true
               _ -> false
             end)

      cleanup_agent(context)
    end
  end

  # ============================================================================
  # Additional tests for better coverage
  # ============================================================================

  describe "restart_agent/2" do
    test "returns error for non-existent agent" do
      {:ok, registry} = start_registry!()
      {:error, _reason} = Lifecycle.restart_agent("non-existent", registry: registry)
    end
  end

  describe "clone_agent/3" do
    test "returns error for non-existent source agent" do
      {:ok, registry} = start_registry!()
      {:error, :not_found} = Lifecycle.clone_agent("non-existent", "clone", registry: registry)
    end
  end

  describe "agent_pid/1" do
    test "returns PID when passed PID" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)

      assert Lifecycle.agent_pid(pid) == pid

      Agent.stop(pid)
    end

    test "returns PID when passed {:ok, pid} tuple" do
      {:ok, pid} = Agent.start_link(fn -> :ok end)

      assert Lifecycle.agent_pid({:ok, pid}) == pid

      Agent.stop(pid)
    end

    test "raises when agent not found by ID" do
      assert_raise RuntimeError, ~r/Agent not found/, fn ->
        Lifecycle.agent_pid("non-existent")
      end
    end
  end

  describe "private helper functions coverage" do
    test "start_agent_by_id with custom module" do
      {:ok, registry} = start_registry!()
      agent_id = unique_id("agent")

      {:ok, pid} =
        Lifecycle.start_agent(agent_id,
          module: BasicAgent,
          registry: registry,
          initial_state: %{battery_level: 50}
        )

      {:ok, state} = Server.state(pid)
      assert state.agent.id == agent_id
      assert state.agent.__struct__ == BasicAgent
      assert state.agent.state.battery_level == 50
    end
  end

  describe "comprehensive error scenarios" do
    test "handles registry lookup errors gracefully" do
      # Test with non-existent registry
      {:error, _reason} = Lifecycle.list_running_agents(registry: NonExistentRegistry)
    end

    @tag :slow
    test "stop_agent handles timeout errors gracefully" do
      {:ok, registry} = start_registry!()

      {:ok, pid} =
        Lifecycle.start_agent(BasicAgent,
          id: "test-agent",
          registry: registry
        )

      # Stop with very short timeout - might succeed or return error
      result = Lifecycle.stop_agent(pid, timeout: 1)

      # Either succeeds immediately or fails gracefully
      assert result == :ok or match?({:error, _}, result)

      Process.sleep(100)
      refute Process.alive?(pid)
    end
  end
end
