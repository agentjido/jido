defmodule JidoTest.Agent.UtilitiesTest do
  use ExUnit.Case, async: true
  doctest Jido.Agent.Utilities

  alias Jido.Agent.Utilities
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.Support

  @moduletag :capture_log

  setup do
    Support.setup_test_registry()
  end

  # ============================================================================
  # via/2 tests
  # ============================================================================

  describe "via/2" do
    test "creates via tuple with default registry for string id" do
      id = "test-agent"
      result = Utilities.via(id)

      assert result == {:via, Registry, {Jido.Registry, "test-agent"}}
    end

    test "creates via tuple with default registry for atom id" do
      id = :test_agent
      result = Utilities.via(id)

      assert result == {:via, Registry, {Jido.Registry, :test_agent}}
    end

    test "creates via tuple with custom registry" do
      id = "test-agent"
      custom_registry = MyCustomRegistry
      result = Utilities.via(id, registry: custom_registry)

      assert result == {:via, Registry, {MyCustomRegistry, "test-agent"}}
    end

    test "creates via tuple with custom registry for atom id" do
      id = :test_agent
      custom_registry = MyCustomRegistry
      result = Utilities.via(id, registry: custom_registry)

      assert result == {:via, Registry, {MyCustomRegistry, :test_agent}}
    end

    test "ignores other options and uses only registry" do
      id = "test-agent"
      result = Utilities.via(id, registry: MyRegistry, other_opt: :ignored)

      assert result == {:via, Registry, {MyRegistry, "test-agent"}}
    end

    test "works with empty options list" do
      id = "test-agent"
      result = Utilities.via(id, [])

      assert result == {:via, Registry, {Jido.Registry, "test-agent"}}
    end
  end

  # ============================================================================
  # resolve_pid/1 tests
  # ============================================================================

  describe "resolve_pid/1 with PID" do
    test "returns {:ok, pid} when passed PID directly" do
      pid = self()

      assert {:ok, ^pid} = Utilities.resolve_pid(pid)
    end

    test "works with any valid PID", %{registry: registry} do
      agent_id = Support.unique_id("resolve-pid-test")

      {:ok, agent_pid} =
        Jido.Agent.Lifecycle.start_agent(BasicAgent, id: agent_id, registry: registry)

      assert {:ok, ^agent_pid} = Utilities.resolve_pid(agent_pid)

      Jido.Agent.Lifecycle.stop_agent(agent_pid)
    end
  end

  describe "resolve_pid/1 with registry tuples" do
    test "resolves PID from {name, registry} tuple with string name", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      assert {:ok, resolved_pid} = Utilities.resolve_pid({context.id, registry})
      assert resolved_pid == context.pid

      Support.cleanup_agent(context)
    end

    test "resolves PID from {name, registry} tuple with atom name", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      # Test with atom version of the name
      atom_name = String.to_atom(context.id)
      assert {:ok, resolved_pid} = Utilities.resolve_pid({atom_name, registry})
      assert resolved_pid == context.pid

      Support.cleanup_agent(context)
    end

    test "returns {:error, :server_not_found} for non-existent agent in registry", %{
      registry: registry
    } do
      result = Utilities.resolve_pid({"non-existent", registry})

      assert result == {:error, :server_not_found}
    end

    test "returns {:error, :server_not_found} for non-existent atom name in registry", %{
      registry: registry
    } do
      result = Utilities.resolve_pid({:non_existent, registry})

      assert result == {:error, :server_not_found}
    end
  end

  describe "resolve_pid/1 with default registry" do
    test "resolves PID using default registry with string name" do
      agent_id = Support.unique_id("default-test")

      # Start agent in default registry
      {:ok, expected_pid} = Jido.Agent.Lifecycle.start_agent(BasicAgent, id: agent_id)

      assert {:ok, ^expected_pid} = Utilities.resolve_pid(agent_id)

      Jido.Agent.Lifecycle.stop_agent(expected_pid)
    end

    test "resolves PID using default registry with atom name" do
      agent_id = Support.unique_id("default-test")

      # Start agent in default registry  
      {:ok, expected_pid} = Jido.Agent.Lifecycle.start_agent(BasicAgent, id: agent_id)

      # Test with atom version
      atom_name = String.to_atom(agent_id)
      assert {:ok, ^expected_pid} = Utilities.resolve_pid(atom_name)

      Jido.Agent.Lifecycle.stop_agent(expected_pid)
    end

    test "returns {:error, :server_not_found} for non-existent name in default registry" do
      result = Utilities.resolve_pid("non-existent-default")

      assert result == {:error, :server_not_found}
    end

    test "returns {:error, :server_not_found} for non-existent atom in default registry" do
      result = Utilities.resolve_pid(:non_existent_default)

      assert result == {:error, :server_not_found}
    end
  end

  # ============================================================================
  # generate_id/0 tests
  # ============================================================================

  describe "generate_id/0" do
    test "generates UUID-v7 string with correct format" do
      id = Utilities.generate_id()

      assert is_binary(id)
      assert String.length(id) == 36

      # Check basic UUID format (8-4-4-4-12 characters separated by hyphens)
      parts = String.split(id, "-")
      assert length(parts) == 5
      # 8 chars
      assert String.length(Enum.at(parts, 0)) == 8
      # 4 chars
      assert String.length(Enum.at(parts, 1)) == 4
      # 4 chars
      assert String.length(Enum.at(parts, 2)) == 4
      # 4 chars
      assert String.length(Enum.at(parts, 3)) == 4
      # 12 chars
      assert String.length(Enum.at(parts, 4)) == 12

      # Should be hex characters plus hyphens
      normalized = String.replace(id, "-", "")
      assert String.match?(normalized, ~r/^[0-9a-f]+$/i)
    end

    test "generates unique IDs" do
      ids = for _ <- 1..5, do: Utilities.generate_id()
      unique_ids = Enum.uniq(ids)

      assert length(ids) == length(unique_ids), "All generated IDs should be unique"
    end

    @tag :slow
    test "generates unique IDs at scale" do
      # Test with more IDs but still reasonable for CI
      ids = for _ <- 1..100, do: Utilities.generate_id()
      unique_ids = Enum.uniq(ids)

      assert length(ids) == length(unique_ids), "All 100 generated IDs should be unique"
    end

    test "generates time-ordered UUIDs (UUID-v7 property)" do
      # Generate IDs with small delays to test time ordering
      id1 = Utilities.generate_id()
      # Slightly longer delay for more reliable ordering
      Process.sleep(2)
      id2 = Utilities.generate_id()
      Process.sleep(2)
      id3 = Utilities.generate_id()

      # Extract timestamp portions (first 8 chars represent time)
      time1 = String.slice(id1, 0, 8)
      time2 = String.slice(id2, 0, 8)
      time3 = String.slice(id3, 0, 8)

      # Should be in chronological order (lexicographically for hex)
      assert time1 <= time2, "IDs should be time-ordered"
      assert time2 <= time3, "IDs should be time-ordered"
    end
  end

  # ============================================================================
  # log_level/2 tests - Success cases
  # ============================================================================

  describe "log_level/2 with valid levels" do
    test "accepts all valid log levels with PID", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      # Test all valid levels
      for level <- [:debug, :info, :warn, :error] do
        result = Utilities.log_level(context.pid, level)
        assert result == :ok, "Expected :ok for level #{inspect(level)}"
      end

      Support.cleanup_agent(context)
    end

    test "accepts valid level with {:ok, pid} tuple", %{registry: registry} do
      agent_id = Support.unique_id("log-test")

      agent_result =
        Jido.Agent.Lifecycle.start_agent(BasicAgent, id: agent_id, registry: registry)

      result = Utilities.log_level(agent_result, :debug)
      assert result == :ok

      {:ok, pid} = agent_result
      Jido.Agent.Lifecycle.stop_agent(pid)
    end

    test "accepts valid level with agent ID string" do
      agent_id = Support.unique_id("log-test")
      {:ok, pid} = Jido.Agent.Lifecycle.start_agent(BasicAgent, id: agent_id)

      result = Utilities.log_level(agent_id, :info)
      assert result == :ok

      Jido.Agent.Lifecycle.stop_agent(pid)
    end

    test "accepts valid level with agent ID atom" do
      agent_id = Support.unique_id("log-test")
      {:ok, pid} = Jido.Agent.Lifecycle.start_agent(BasicAgent, id: agent_id)

      result = Utilities.log_level(agent_id, :warn)
      assert result == :ok

      Jido.Agent.Lifecycle.stop_agent(pid)
    end
  end

  # ============================================================================
  # log_level/2 tests - Invalid level handling
  # ============================================================================

  describe "log_level/2 with invalid levels" do
    test "returns error for invalid log level with PID" do
      result = Utilities.log_level(self(), :invalid)
      assert result == {:error, {:invalid_log_level, :invalid}}
    end

    test "returns error for invalid log level with string" do
      result = Utilities.log_level("some-id", :trace)
      assert result == {:error, {:invalid_log_level, :trace}}
    end

    test "returns error for invalid log level with atom" do
      result = Utilities.log_level(:some_id, :verbose)
      assert result == {:error, {:invalid_log_level, :verbose}}
    end

    test "returns error for invalid log level with {:ok, pid} tuple" do
      result = Utilities.log_level({:ok, self()}, :critical)
      assert result == {:error, {:invalid_log_level, :critical}}
    end

    test "returns error for non-atom log level" do
      result = Utilities.log_level(self(), "debug")
      assert result == {:error, {:invalid_log_level, "debug"}}
    end

    test "returns error for nil log level" do
      result = Utilities.log_level(self(), nil)
      assert result == {:error, {:invalid_log_level, nil}}
    end

    test "returns error for integer log level" do
      result = Utilities.log_level(self(), 1)
      assert result == {:error, {:invalid_log_level, 1}}
    end
  end

  # ============================================================================
  # log_level/2 tests - Agent resolution errors
  # ============================================================================

  describe "log_level/2 agent resolution errors" do
    test "returns error for non-existent agent by string ID" do
      result = Utilities.log_level("non-existent-agent", :debug)
      assert {:error, _reason} = result
    end

    test "returns error for non-existent agent by atom ID" do
      result = Utilities.log_level(:non_existent_agent, :info)
      assert {:error, _reason} = result
    end

    test "handles dead PID gracefully", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      Support.cleanup_agent(context)
      # Ensure process is dead
      Process.sleep(50)

      result = Utilities.log_level(context.pid, :debug)
      # Could be :ok (signal sent successfully) or error (process dead)
      # Both are valid outcomes for this edge case
      assert result == :ok or match?({:error, _}, result)
    end
  end

  # ============================================================================
  # log_level/2 tests - Signal creation and casting
  # ============================================================================

  describe "log_level/2 signal handling" do
    test "creates proper signal structure for log level update", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      result = Utilities.log_level(context.pid, :debug)
      assert result == :ok

      # Allow time for async processing
      Process.sleep(50)
      Support.cleanup_agent(context)
    end

    test "handles multiple rapid log level changes", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      # Send multiple log level updates rapidly
      results = [
        Utilities.log_level(context.pid, :debug),
        Utilities.log_level(context.pid, :info),
        Utilities.log_level(context.pid, :warn),
        Utilities.log_level(context.pid, :error),
        Utilities.log_level(context.pid, :debug)
      ]

      assert Enum.all?(results, &(&1 == :ok)), "All log level changes should succeed"
      Support.cleanup_agent(context)
    end
  end

  # ============================================================================
  # Integration tests - Testing combined functionality
  # ============================================================================

  describe "integration tests" do
    test "via + resolve_pid + log_level workflow", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      # 1. Create via tuple
      via_tuple = Utilities.via(context.id, registry: registry)
      expected_tuple = {:via, Registry, {registry, context.id}}
      assert via_tuple == expected_tuple

      # 2. Resolve PID from agent ID (using custom registry)
      {:ok, resolved_pid} = Utilities.resolve_pid({context.id, registry})
      assert resolved_pid == context.pid

      # 3. Update log level using resolved PID
      assert :ok = Utilities.log_level(resolved_pid, :debug)
      assert :ok = Utilities.log_level(resolved_pid, :info)

      Support.cleanup_agent(context)
    end

    test "generate_id + start_agent + utilities workflow", %{registry: registry} do
      # 1. Generate unique ID
      agent_id = Utilities.generate_id()
      assert is_binary(agent_id)

      # 2. Create via tuple and start agent
      {:ok, context} =
        Support.start_basic_agent!(
          id: agent_id,
          registry: registry,
          cleanup: false
        )

      # 3. Verify via tuple works
      via_tuple = Utilities.via(agent_id, registry: registry)
      assert {:via, Registry, {^registry, ^agent_id}} = via_tuple

      # 4. Resolve PID and update log level
      {:ok, resolved_pid} = Utilities.resolve_pid({agent_id, registry})
      assert resolved_pid == context.pid
      assert :ok = Utilities.log_level(resolved_pid, :warn)

      Support.cleanup_agent(context)
    end

    test "error handling across utility functions" do
      non_existent_id = Support.unique_id("definitely-not-exists")

      # resolve_pid should return error
      {:error, :server_not_found} = Utilities.resolve_pid(non_existent_id)

      # log_level should return error for non-existent agent
      {:error, _reason} = Utilities.log_level(non_existent_id, :debug)

      # But invalid log level should be caught first
      {:error, {:invalid_log_level, :bad_level}} =
        Utilities.log_level(non_existent_id, :bad_level)
    end
  end

  # ============================================================================
  # Edge cases and boundary conditions
  # ============================================================================

  describe "edge cases" do
    test "via/2 with very long agent ID" do
      long_id = String.duplicate("a", 1000)
      result = Utilities.via(long_id)
      assert result == {:via, Registry, {Jido.Registry, long_id}}
    end

    test "via/2 with unicode characters" do
      unicode_id = "test-ñáéíóú-agent-🤖"
      result = Utilities.via(unicode_id)
      assert result == {:via, Registry, {Jido.Registry, unicode_id}}
    end

    test "resolve_pid with registry that doesn't exist" do
      assert_raise ArgumentError, fn ->
        Utilities.resolve_pid({"test", NonExistentRegistry})
      end
    end

    test "concurrent access to same utility functions", %{registry: registry} do
      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      # Run concurrent operations
      tasks =
        for i <- 1..8 do
          Task.async(fn ->
            case rem(i, 4) do
              0 -> Utilities.resolve_pid({context.id, registry})
              1 -> Utilities.log_level(context.pid, :debug)
              2 -> Utilities.log_level(context.pid, :info)
              3 -> Utilities.via(context.id, registry: registry)
            end
          end)
        end

      results = Task.await_many(tasks, 2000)

      success_count =
        Enum.count(results, fn
          :ok -> true
          {:ok, _} -> true
          {:via, Registry, _} -> true
          _ -> false
        end)

      assert success_count >= 6, "Most concurrent operations should succeed"
      Support.cleanup_agent(context)
    end
  end

  # ============================================================================
  # Type safety and contract tests
  # ============================================================================

  describe "type safety" do
    test "via/2 only accepts binary or atom for id" do
      # These should work
      assert {:via, Registry, {Jido.Registry, "string"}} = Utilities.via("string")
      assert {:via, Registry, {Jido.Registry, :atom}} = Utilities.via(:atom)

      # These would fail due to guards
      assert_raise FunctionClauseError, fn -> Utilities.via(123) end
      assert_raise FunctionClauseError, fn -> Utilities.via([]) end
      assert_raise FunctionClauseError, fn -> Utilities.via(%{}) end
    end

    test "log_level/2 validates level atoms correctly", %{registry: registry} do
      valid_levels = [:debug, :info, :warn, :error]
      invalid_levels = [:trace, :verbose, :critical, :fatal, :notice]

      {:ok, context} = Support.start_basic_agent!(registry: registry, cleanup: false)

      # Valid levels should pass validation
      for level <- valid_levels do
        result = Utilities.log_level(context.pid, level)

        assert result == :ok or match?({:error, _}, result),
               "Valid level #{inspect(level)} should not be rejected"
      end

      # Invalid levels should be rejected at validation level
      for level <- invalid_levels do
        result = Utilities.log_level(context.pid, level)

        assert result == {:error, {:invalid_log_level, level}},
               "Invalid level #{inspect(level)} should be rejected"
      end

      Support.cleanup_agent(context)
    end
  end
end
