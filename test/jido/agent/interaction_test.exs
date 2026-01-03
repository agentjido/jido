defmodule JidoTest.Agent.InteractionTest do
  use JidoTest.Case, async: true
  doctest Jido.Agent.Interaction

  alias Jido.Agent.Interaction
  alias Jido.{Signal, Instruction}
  alias JidoTest.TestActions
  alias JidoTest.Support

  @moduletag :capture_log

  setup do
    {:ok, registry} = Support.start_registry!()

    route = Support.create_test_route("test_action", TestActions.BasicAction, %{value: 42})

    agent_id = Support.unique_id("test-agent")

    {:ok, pid} =
      Jido.Agent.Server.start_link(
        agent: JidoTest.TestAgents.BasicAgent,
        id: agent_id,
        registry: registry,
        routes: [route]
      )

    context = %{
      pid: pid,
      agent_id: agent_id,
      registry: registry
    }

    ExUnit.Callbacks.on_exit(fn -> Support.cleanup_agent(context) end)

    context
  end

  describe "call/3" do
    test "calls agent with PID and Signal", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.call(pid, signal)
      assert {:ok, _response} = result
    end

    test "calls agent with PID and Instruction", %{pid: pid} do
      {:ok, instruction} =
        Instruction.new(%{action: TestActions.BasicAction, params: %{value: 42}})

      result = Interaction.call(pid, instruction)
      assert {:ok, %{value: 42}} = result
    end

    test "calls agent with {:ok, pid} tuple and Signal", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.call({:ok, pid}, signal)
      assert {:ok, _response} = result
    end

    test "calls agent with {:ok, pid} tuple and Instruction", %{pid: pid} do
      {:ok, instruction} =
        Instruction.new(%{action: TestActions.BasicAction, params: %{value: 42}})

      result = Interaction.call({:ok, pid}, instruction)
      assert {:ok, %{value: 42}} = result
    end

    test "calls agent with custom timeout", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})
      timeout = 10_000

      result = Interaction.call(pid, signal, timeout)
      assert {:ok, _response} = result
    end

    test "returns error when agent not found" do
      non_existent_id = "non-existent-agent"
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.call(non_existent_id, signal)
      assert {:error, :not_found} = result
    end

    @tag :slow
    test "returns error for invalid signal", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "nonexistent_route", data: %{}})

      result = Interaction.call(pid, signal, 1000)
      assert {:error, _error} = result
    end
  end

  describe "cast/2" do
    test "casts signal to agent with PID", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.cast(pid, signal)
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "casts instruction to agent with PID", %{pid: pid} do
      {:ok, instruction} =
        Instruction.new(%{action: TestActions.BasicAction, params: %{value: 42}})

      result = Interaction.cast(pid, instruction)
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "casts to agent with {:ok, pid} tuple", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.cast({:ok, pid}, signal)
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "returns error when agent not found for cast" do
      non_existent_id = "non-existent-cast-agent"
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.cast(non_existent_id, signal)
      assert {:error, :not_found} = result
    end

    test "handles cast with invalid signal gracefully", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "nonexistent_route", data: %{}})

      # Cast should still succeed (fire-and-forget), even with invalid routes
      result = Interaction.cast(pid, signal)
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end
  end

  describe "send_signal/4" do
    test "sends signal basic", %{pid: pid} do
      result = Interaction.send_signal(pid, "test_action", %{value: 42}, [])
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "sends signal with_options", %{pid: pid} do
      result =
        Interaction.send_signal(pid, "test_action", %{value: 42},
          source: "api_server",
          subject: "task_processor"
        )

      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "sends signal with_dispatch", %{pid: pid} do
      result =
        Interaction.send_signal(pid, "test_action", %{value: 42}, dispatch: {:noop, []})

      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "sends signal filtered_options", %{pid: pid} do
      result =
        Interaction.send_signal(pid, "test_action", %{value: 42},
          source: "test",
          invalid_option: "ignored",
          subject: "valid"
        )

      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "returns error when signal building fails" do
      # Dead process
      invalid_pid = spawn(fn -> :ok end)
      type = nil
      data = %{}

      result = Interaction.send_signal(invalid_pid, type, data)
      assert {:error, _reason} = result
    end

    test "returns error for non-existent agent" do
      non_existent_id = "non-existent-signal-agent"
      type = "test_action"
      data = %{value: 42}

      result = Interaction.send_signal(non_existent_id, type, data)
      assert {:error, :not_found} = result
    end
  end

  describe "send_instruction/4" do
    test "sends instruction basic", %{pid: pid} do
      result = Interaction.send_instruction(pid, TestActions.BasicAction, %{value: 42}, [])
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "sends instruction with_context", %{pid: pid} do
      result =
        Interaction.send_instruction(pid, TestActions.BasicAction, %{value: 42},
          context: %{user_id: "user-456", session: "sess-789"},
          priority: :high
        )

      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "sends instruction with_id", %{pid: pid} do
      result =
        Interaction.send_instruction(pid, TestActions.BasicAction, %{value: 42},
          id: "custom-instruction-id"
        )

      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "sends instruction nil_params", %{pid: pid} do
      result = Interaction.send_instruction(pid, TestActions.BasicAction, nil, [])
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "returns error for non-existent agent" do
      non_existent_id = "non-existent-instruction-agent"
      action = TestActions.BasicAction
      params = %{value: 42}

      result = Interaction.send_instruction(non_existent_id, action, params)
      assert {:error, :not_found} = result
    end

    test "handles invalid action gracefully", %{pid: pid} do
      action = nil
      params = %{value: 42}

      result = Interaction.send_instruction(pid, action, params)

      case result do
        {:ok, correlation_id} when is_binary(correlation_id) -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "request/4" do
    test "request sync_instruction_default", %{pid: pid} do
      result = Interaction.request(pid, TestActions.BasicAction, %{value: 42}, [])
      assert {:ok, %{value: 42}} = result
    end

    test "request sync_signal", %{pid: pid} do
      result = Interaction.request(pid, "test_action", %{value: 42}, type: :signal, mode: :sync)
      assert {:ok, _response} = result
    end

    test "request async_instruction", %{pid: pid} do
      result =
        Interaction.request(pid, TestActions.BasicAction, %{value: 42},
          type: :instruction,
          mode: :async
        )

      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "request async_signal", %{pid: pid} do
      result = Interaction.request(pid, "test_action", %{value: 42}, type: :signal, mode: :async)
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "request custom_timeout", %{pid: pid} do
      result = Interaction.request(pid, TestActions.BasicAction, %{value: 42}, timeout: 10_000)
      assert {:ok, %{value: 42}} = result
    end

    test "request signal_options", %{pid: pid} do
      result =
        Interaction.request(pid, "test_action", %{value: 42},
          type: :signal,
          source: "test_source",
          subject: "test_subject"
        )

      assert {:ok, _response} = result
    end

    test "request instruction_options", %{pid: pid} do
      result =
        Interaction.request(pid, TestActions.BasicAction, %{value: 42},
          type: :instruction,
          context: %{user: "test"},
          id: "custom-id"
        )

      assert {:ok, %{value: 42}} = result
    end

    test "returns error for invalid_mode", %{pid: pid} do
      path = TestActions.BasicAction
      payload = %{value: 42}

      result = Interaction.request(pid, path, payload, mode: :invalid_mode)
      assert {:error, {:invalid_mode, :invalid_mode}} = result
    end

    test "returns error for invalid_type", %{pid: pid} do
      path = TestActions.BasicAction
      payload = %{value: 42}

      result = Interaction.request(pid, path, payload, type: :invalid_type)
      assert {:error, {:invalid_type, :invalid_type}} = result
    end

    test "works with {:ok, pid} tuple", %{pid: pid} do
      path = TestActions.BasicAction
      payload = %{value: 42}

      result = Interaction.request({:ok, pid}, path, payload)
      assert {:ok, %{value: 42}} = result
    end

    test "returns error for non-existent agent" do
      non_existent_id = "non-existent-request-agent"
      path = TestActions.BasicAction
      payload = %{value: 42}

      result = Interaction.request(non_existent_id, path, payload)
      assert {:error, :not_found} = result
    end
  end

  describe "edge cases and error handling" do
    test "handles invalid agent references gracefully" do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      # Test atom reference separately (fixed atom is fine - no collision risk)
      assert {:error, :not_found} = Interaction.call(:non_existent_atom_agent, signal)

      # Use unique IDs for string refs to avoid async test collisions
      invalid_refs = [
        Support.unique_id("non-existent"),
        Support.unique_id("non-existent"),
        Support.unique_id("non-existent")
      ]

      for ref <- invalid_refs do
        assert {:error, :not_found} = Interaction.call(ref, signal)
        assert {:error, :not_found} = Interaction.cast(ref, signal)
        assert {:error, :not_found} = Interaction.send_signal(ref, "test_action", %{value: 42})

        assert {:error, :not_found} =
                 Interaction.send_instruction(ref, TestActions.BasicAction, %{value: 42})

        assert {:error, :not_found} =
                 Interaction.request(ref, TestActions.BasicAction, %{value: 42})
      end
    end

    @tag :slow
    test "handles large payloads", %{pid: pid} do
      # Test with large data payload
      large_data = for i <- 1..100, into: %{}, do: {"key_#{i}", "value_#{i}"}

      result = Interaction.send_signal(pid, "test_action", large_data)
      assert {:ok, correlation_id} = result
      assert is_binary(correlation_id)
    end

    test "handles empty and nil options", %{pid: pid} do
      # Test with nil and empty options
      result1 = Interaction.send_signal(pid, "test_action", %{value: 42}, [])
      assert {:ok, correlation_id1} = result1
      assert is_binary(correlation_id1)

      result2 = Interaction.send_signal(pid, "test_action", %{value: 42})
      assert {:ok, correlation_id2} = result2
      assert is_binary(correlation_id2)
    end

    @tag :slow
    test "handles invalid agent references in calls" do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      result = Interaction.call("non-existent-agent", signal, 100)
      assert {:error, :not_found} = result
    end

    test "agent reference type conversion", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_action", data: %{value: 42}})

      # Test that all reference types work
      assert {:ok, _} = Interaction.call(pid, signal)
      assert {:ok, _} = Interaction.call({:ok, pid}, signal)

      # String/atom IDs would require proper registry setup in real usage
      assert {:error, :not_found} = Interaction.call("test-id", signal)
    end

    test "handles malformed messages gracefully" do
      non_existent_id = "absolutely-does-not-exist-#{System.unique_integer([:positive])}"

      # These should fail due to agent not found
      assert {:error, _} = Interaction.send_signal(non_existent_id, nil, %{})
      assert {:error, _} = Interaction.request(non_existent_id, nil, %{})
    end

    test "validates function parameters" do
      non_existent_agent = "definitely-does-not-exist"

      # All these should return proper error tuples, not crash
      assert {:error, _} = Interaction.call(non_existent_agent, %{invalid: "message"})
      assert {:error, _} = Interaction.cast(non_existent_agent, %{invalid: "message"})
    end
  end
end
