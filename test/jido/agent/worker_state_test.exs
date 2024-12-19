defmodule Jido.Agent.Worker.StateTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Worker.State
  alias JidoTest.SimpleAgent

  describe "new state" do
    test "creates state with required fields" do
      agent = SimpleAgent.new("test")
      state = %State{agent: agent, pubsub: TestPubSub, topic: "test"}

      assert state.agent == agent
      assert state.pubsub == TestPubSub
      assert state.topic == "test"
      assert state.status == :idle
      assert :queue.is_queue(state.pending)
      assert :queue.is_empty(state.pending)
    end
  end

  describe "transition/2" do
    setup do
      agent = SimpleAgent.new("test")
      state = %State{agent: agent, pubsub: TestPubSub, topic: "test"}
      {:ok, state: state}
    end

    test "allows valid transitions", %{state: state} do
      # initializing -> idle
      state = %{state | status: :initializing}
      assert {:ok, %State{status: :idle}} = State.transition(state, :idle)

      # idle -> planning
      state = %{state | status: :idle}
      assert {:ok, %State{status: :planning}} = State.transition(state, :planning)

      # planning -> running
      state = %{state | status: :planning}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)

      # running -> paused
      state = %{state | status: :running}
      assert {:ok, %State{status: :paused}} = State.transition(state, :paused)

      # paused -> running
      state = %{state | status: :paused}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)
    end

    test "rejects invalid transitions", %{state: state} do
      # Can't go from idle to paused
      state = %{state | status: :idle}
      assert {:error, {:invalid_transition, :idle, :paused}} = State.transition(state, :paused)

      # Can't go from running to planning
      state = %{state | status: :running}

      assert {:error, {:invalid_transition, :running, :planning}} =
               State.transition(state, :planning)
    end
  end

  describe "default_topic/1" do
    test "generates topic from agent id" do
      assert State.default_topic("test_agent") == "jido.agent.test_agent"
    end
  end
end
