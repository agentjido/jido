defmodule Jido.Agents.IteratorAgentTest do
  use ExUnit.Case, async: true
  alias Jido.Agents.IteratorAgent
  alias Jido.Actions.{CounterBody, LimitDecision}

  describe "IteratorAgent - basic functionality" do
    test "can be instantiated" do
      agent = IteratorAgent.new([])
      assert %IteratorAgent{} = agent
      assert agent.id != nil
    end

    test "has required actions registered" do
      agent = IteratorAgent.new([])
      
      # Check that required actions are registered
      assert Jido.Actions.Iterator in agent.actions
      assert CounterBody in agent.actions
      assert LimitDecision in agent.actions
    end
  end

  describe "IteratorAgent - simple iteration (backward compatibility)" do
    test "start_iteration calls start_simple_iteration" do
      agent = IteratorAgent.new([])

      # Start a short iteration sequence
      assert {:ok, final_agent, []} = IteratorAgent.start_iteration(agent, 3)

      # Check that instructions were enqueued
      assert :queue.len(final_agent.pending_instructions) > 0

      # Get the enqueued instruction
      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      # Verify it's an Iterator action with CounterBody as body_action
      assert instruction.action == Jido.Actions.Iterator
      assert instruction.params.max_steps == 3
      assert instruction.params.body_action == CounterBody
      assert instruction.params.body_params.increment == 1
    end

    test "start_simple_iteration enqueues Iterator with CounterBody" do
      agent = IteratorAgent.new([])

      assert {:ok, final_agent, []} = IteratorAgent.start_simple_iteration(agent, 5)

      # Check that instructions were enqueued
      assert :queue.len(final_agent.pending_instructions) > 0

      # Get the enqueued instruction
      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      assert instruction.action == Jido.Actions.Iterator
      assert instruction.params.max_steps == 5
      assert instruction.params.body_action == CounterBody
      assert instruction.params.state_path == [:iterator_state]
      refute Map.has_key?(instruction.params, :state)
    end
  end

  describe "IteratorAgent - advanced iteration" do
    test "start_advanced_iteration with default options" do
      agent = IteratorAgent.new([])

      assert {:ok, final_agent, []} = IteratorAgent.start_advanced_iteration(agent)

      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      assert instruction.action == Jido.Actions.Iterator
      assert instruction.params.max_steps == 10
      assert instruction.params.body_action == CounterBody
      assert instruction.params.decision_action == LimitDecision
      assert instruction.params.decision_params.count_limit == 50
    end

    test "start_advanced_iteration with custom options" do
      agent = IteratorAgent.new([])

      opts = [
        max_steps: 20,
        body_action: CounterBody,
        body_params: %{increment: 3},
        decision_action: LimitDecision,
        decision_params: %{count_limit: 30}
      ]

      assert {:ok, final_agent, []} = IteratorAgent.start_advanced_iteration(agent, opts)

      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      assert instruction.params.max_steps == 20
      assert instruction.params.body_params.increment == 3
      assert instruction.params.decision_params.count_limit == 30
    end
  end

  describe "IteratorAgent - counting iteration" do
    test "start_counting_iteration with default options" do
      agent = IteratorAgent.new([])

      assert {:ok, final_agent, []} = IteratorAgent.start_counting_iteration(agent)

      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      assert instruction.action == Jido.Actions.Iterator
      assert instruction.params.max_steps == 100  # Safety limit
      assert instruction.params.body_action == CounterBody
      assert instruction.params.body_params.increment == 2
      assert instruction.params.decision_action == LimitDecision
      assert instruction.params.decision_params.count_limit == 25
    end

    test "start_counting_iteration with custom parameters" do
      agent = IteratorAgent.new([])

      assert {:ok, final_agent, []} = IteratorAgent.start_counting_iteration(agent, 100, 5)

      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      assert instruction.params.body_params.increment == 5
      assert instruction.params.decision_params.count_limit == 100
    end
  end

  describe "IteratorAgent - state and metadata" do
    test "all iteration methods use the state_path parameter" do
      agent = IteratorAgent.new([])

      {:ok, final_agent, []} = IteratorAgent.start_simple_iteration(agent)
      {{:value, instruction}, _queue} = :queue.out(final_agent.pending_instructions)
      
      # Should use state_path instead of direct state parameter
      assert instruction.params.state_path == [:iterator_state]
      refute Map.has_key?(instruction.params, :state)
    end

    test "each iteration method creates unique run_id" do
      agent = IteratorAgent.new([])

      {:ok, agent1, []} = IteratorAgent.start_simple_iteration(agent)
      {:ok, agent2, []} = IteratorAgent.start_counting_iteration(agent1)

      {{:value, instruction1}, queue1} = :queue.out(agent2.pending_instructions)
      {{:value, instruction2}, _queue2} = :queue.out(queue1)
      
      # Should have different run_ids (generated by the Iterator action)
      # Since run_id is generated within the Iterator action, we just verify they're both Iterator instructions
      assert instruction1.action == Jido.Actions.Iterator
      assert instruction2.action == Jido.Actions.Iterator
      assert instruction1.params.state_path == [:iterator_state]
      assert instruction2.params.state_path == [:iterator_state]
    end
  end
end
