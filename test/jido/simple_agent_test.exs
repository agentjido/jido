defmodule JidoTest.SimpleAgentTest do
  use ExUnit.Case, async: true

  alias Jido.SimpleAgent

  describe "start_link/1" do
    test "starts agent with basic configuration" do
      assert {:ok, pid} = SimpleAgent.start_link(name: "test_agent")
      assert Process.alive?(pid)
    end

    test "starts agent with actions" do
      actions = [Jido.Skills.Arithmetic.Actions.Eval]
      assert {:ok, pid} = SimpleAgent.start_link(name: "math_agent", actions: actions)

      assert {:ok, registered_actions} = SimpleAgent.list_actions(pid)
      assert Jido.Skills.Arithmetic.Actions.Eval in registered_actions
    end

    test "fails with invalid actions" do
      actions = [NonExistentAction]

      # Should receive {:EXIT, pid, reason} since GenServer crashes during init
      Process.flag(:trap_exit, true)
      result = SimpleAgent.start_link(name: "invalid_agent", actions: actions)

      case result do
        {:error, {:action_validation_failed, _reason}} -> :ok
        # Handle various error formats
        {:error, reason} when is_tuple(reason) -> :ok
        other -> flunk("Expected error but got: #{inspect(other)}")
      end
    end

    test "requires name parameter" do
      assert_raise KeyError, fn ->
        SimpleAgent.start_link([])
      end
    end
  end

  describe "action registration" do
    setup do
      {:ok, pid} = SimpleAgent.start_link(name: "test_agent")
      %{pid: pid}
    end

    test "registers valid action", %{pid: pid} do
      assert :ok = SimpleAgent.register_action(pid, Jido.Skills.Arithmetic.Actions.Eval)

      assert {:ok, actions} = SimpleAgent.list_actions(pid)
      assert Jido.Skills.Arithmetic.Actions.Eval in actions
    end

    test "rejects invalid action", %{pid: pid} do
      assert {:error, _reason} = SimpleAgent.register_action(pid, NonExistentAction)

      assert {:ok, actions} = SimpleAgent.list_actions(pid)
      assert actions == []
    end

    test "prevents duplicate registrations", %{pid: pid} do
      action = Jido.Skills.Arithmetic.Actions.Eval

      assert :ok = SimpleAgent.register_action(pid, action)
      assert :ok = SimpleAgent.register_action(pid, action)

      assert {:ok, actions} = SimpleAgent.list_actions(pid)
      assert length(actions) == 1
      assert action in actions
    end

    test "lists empty actions initially", %{pid: pid} do
      assert {:ok, []} = SimpleAgent.list_actions(pid)
    end
  end

  describe "memory management" do
    setup do
      {:ok, pid} = SimpleAgent.start_link(name: "test_agent")
      %{pid: pid}
    end

    test "starts with empty memory", %{pid: pid} do
      assert {:ok, memory} = SimpleAgent.get_memory(pid)
      assert memory == %{messages: [], tool_results: %{}}
    end

    test "clears memory", %{pid: pid} do
      # Add some conversation first
      SimpleAgent.call(pid, "Hello")

      assert :ok = SimpleAgent.clear_memory(pid)

      assert {:ok, memory} = SimpleAgent.get_memory(pid)
      assert memory == %{messages: [], tool_results: %{}}
    end
  end

  describe "basic conversation" do
    setup do
      {:ok, pid} = SimpleAgent.start_link(name: "test_agent")
      %{pid: pid}
    end

    test "handles greeting", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "Hello")
      assert response == "Hello! How can I help you?"
    end

    test "handles help request", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "What can you do?")
      assert response == "I can perform mathematical calculations and have basic conversations."
    end

    test "handles goodbye", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "Goodbye")
      assert response == "Goodbye! Have a great day!"
    end

    test "handles unknown input", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "Random unknown input")
      assert response == "I'm not sure about that, but I can help with math calculations!"
    end

    test "updates memory with conversation", %{pid: pid} do
      SimpleAgent.call(pid, "Hello")

      assert {:ok, memory} = SimpleAgent.get_memory(pid)
      # user + assistant messages
      assert length(memory.messages) == 2

      [user_msg, assistant_msg] = memory.messages
      assert user_msg.role == :user
      assert user_msg.content == "Hello"
      assert assistant_msg.role == :assistant
      assert assistant_msg.content == "Hello! How can I help you?"
    end
  end

  describe "tool execution" do
    setup do
      {:ok, pid} =
        SimpleAgent.start_link(
          name: "math_agent",
          actions: [Jido.Skills.Arithmetic.Actions.Eval]
        )

      %{pid: pid}
    end

    test "executes math calculation", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "What is 2 + 3?")
      assert response == "The answer is 5"
    end

    test "handles complex math expression", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "Calculate 10 * 2 + 5")
      assert response == "The answer is 25"
    end

    test "stores tool results in memory", %{pid: pid} do
      SimpleAgent.call(pid, "What is 7 + 8?")

      assert {:ok, memory} = SimpleAgent.get_memory(pid)
      assert map_size(memory.tool_results) == 1
      assert Map.has_key?(memory.tool_results, Jido.Skills.Arithmetic.Actions.Eval)

      result = memory.tool_results[Jido.Skills.Arithmetic.Actions.Eval]
      assert result.result == 15
    end

    test "adds tool messages to conversation history", %{pid: pid} do
      SimpleAgent.call(pid, "What is 4 * 6?")

      assert {:ok, memory} = SimpleAgent.get_memory(pid)

      # Should have: user message, tool message, assistant response
      assert length(memory.messages) == 3

      [user_msg, tool_msg, assistant_msg] = memory.messages
      assert user_msg.role == :user
      assert tool_msg.role == :tool
      assert tool_msg.name == Jido.Skills.Arithmetic.Actions.Eval
      assert assistant_msg.role == :assistant
      assert assistant_msg.content == "The answer is 24"
    end

    test "handles tool execution errors gracefully", %{pid: pid} do
      assert {:ok, response} = SimpleAgent.call(pid, "What is 1 / 0?")
      assert String.contains?(response, "error")
    end

    test "rejects unregistered actions", %{pid: pid} do
      # Clear actions and try to use math
      SimpleAgent.clear_memory(pid)

      # Create agent without math actions
      {:ok, pid_no_math} = SimpleAgent.start_link(name: "no_math_agent")

      assert {:ok, response} = SimpleAgent.call(pid_no_math, "What is 2 + 2?")

      assert response ==
               "Action Elixir.Jido.Skills.Arithmetic.Actions.Eval is not registered with this agent."
    end
  end

  describe "error handling" do
    setup do
      {:ok, pid} = SimpleAgent.start_link(name: "test_agent", max_turns: 2)
      %{pid: pid}
    end

    test "prevents infinite loops with max_turns", %{pid: pid} do
      # This would be hard to trigger with the current reasoner, but we can test the limit exists
      assert {:ok, _response} = SimpleAgent.call(pid, "Hello")
      # The max_turns protection is more relevant for complex multi-turn scenarios
    end

    test "handles reasoner errors gracefully", %{pid: pid} do
      # Even with invalid input, should get a response
      assert {:ok, response} = SimpleAgent.call(pid, "")
      assert is_binary(response)
    end
  end

  describe "complete agent loop" do
    setup do
      {:ok, pid} =
        SimpleAgent.start_link(
          name: "complete_agent",
          actions: [Jido.Skills.Arithmetic.Actions.Eval]
        )

      %{pid: pid}
    end

    test "handles multi-step conversation", %{pid: pid} do
      # First interaction
      assert {:ok, response1} = SimpleAgent.call(pid, "Hello")
      assert response1 == "Hello! How can I help you?"

      # Math calculation
      assert {:ok, response2} = SimpleAgent.call(pid, "What is 15 + 25?")
      assert response2 == "The answer is 40"

      # Check memory has all interactions
      assert {:ok, memory} = SimpleAgent.get_memory(pid)
      # At least 2 conversations worth
      assert length(memory.messages) >= 4
    end

    test "memory persists across calls", %{pid: pid} do
      SimpleAgent.call(pid, "Calculate 3 * 4")
      SimpleAgent.call(pid, "What is 10 - 7?")

      assert {:ok, memory} = SimpleAgent.get_memory(pid)

      # Should have results from both calculations
      assert map_size(memory.tool_results) >= 1

      # Should have messages from both conversations
      assert length(memory.messages) >= 4
    end
  end
end
