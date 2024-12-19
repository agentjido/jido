defmodule Jido.Agent.WorkerProcessTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Agent.Worker
  alias Jido.Agent.Worker.State
  alias JidoTest.SimpleAgent

  setup do
    Logger.configure(level: :debug)
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, _} = start_supervised({Registry, keys: :unique, name: Jido.AgentRegistry})
    agent = SimpleAgent.new("test_agent")
    {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
    %{worker: pid, agent: agent}
  end

  describe "validate_state/1" do
    test "validates state with valid inputs", %{worker: pid} do
      state = :sys.get_state(pid)
      assert :ok = Worker.validate_state(state)
    end

    test "fails validation with nil pubsub" do
      state = %State{pubsub: nil, agent: SimpleAgent.new("test"), topic: "test"}
      assert {:error, "PubSub module is required"} = Worker.validate_state(state)
    end

    test "fails validation with nil agent" do
      state = %State{pubsub: TestPubSub, agent: nil, topic: "test"}
      assert {:error, "Agent is required"} = Worker.validate_state(state)
    end
  end

  describe "process_signal/2" do
    test "processes act signal", %{worker: pid} do
      state = :sys.get_state(pid)

      {:ok, signal} =
        Signal.new(%{type: "jido.agent.act", source: "/test", data: %{command: :move}})

      assert {:ok, _new_state} = Worker.process_signal(signal, state)
    end

    test "processes manage signal", %{worker: pid} do
      state = :sys.get_state(pid)

      {:ok, signal} =
        Signal.new(%{
          type: "jido.agent.manage",
          source: "/test",
          data: %{command: :pause, args: nil}
        })

      assert {:ok, new_state} = Worker.process_signal(signal, state)
      assert new_state.status == :paused
    end

    test "ignores unknown signal type", %{worker: pid} do
      state = :sys.get_state(pid)
      {:ok, signal} = Signal.new(%{type: "unknown", source: "/test", data: %{}})
      assert :ignore = Worker.process_signal(signal, state)
    end
  end

  describe "process_act/2" do
    test "queues act when paused", %{worker: pid} do
      {:ok, paused_state} = Worker.manage(pid, :pause)
      attrs = %{command: :move}
      assert {:ok, new_state} = Worker.process_act(attrs, paused_state)
      assert :queue.len(new_state.pending) == 1
    end

    test "processes act with command when idle", %{worker: pid} do
      state = :sys.get_state(pid)
      attrs = %{command: :move, location: :kitchen}
      assert {:ok, new_state} = Worker.process_act(attrs, state)
      assert new_state.agent.location == :kitchen
      assert new_state.status == :idle
    end

    test "processes act with default command when no command given", %{worker: pid} do
      state = :sys.get_state(pid)
      attrs = %{location: :kitchen}
      assert {:ok, new_state} = Worker.process_act(attrs, state)
      assert new_state.agent.location == :kitchen
      assert new_state.status == :idle
    end
  end

  describe "process_manage/4" do
    test "pauses agent", %{worker: pid} do
      state = :sys.get_state(pid)
      assert {:ok, new_state} = Worker.process_manage(:pause, nil, nil, state)
      assert new_state.status == :paused
    end

    test "resumes paused agent", %{worker: pid} do
      {:ok, paused_state} = Worker.manage(pid, :pause)
      assert {:ok, new_state} = Worker.process_manage(:resume, nil, nil, paused_state)
      assert new_state.status == :running
    end

    test "resets agent state", %{worker: pid} do
      # Queue up some commands first
      {:ok, paused_state} = Worker.manage(pid, :pause)
      {:ok, state_with_pending} = Worker.process_act(%{command: :move}, paused_state)
      assert :queue.len(state_with_pending.pending) > 0

      assert {:ok, new_state} = Worker.process_manage(:reset, nil, nil, state_with_pending)
      assert new_state.status == :idle
      assert :queue.len(new_state.pending) == 0
    end

    test "returns error for invalid command", %{worker: pid} do
      state = :sys.get_state(pid)
      assert {:error, :invalid_command} = Worker.process_manage(:invalid, nil, nil, state)
    end
  end

  describe "process_pending_commands/1" do
    test "processes queued commands when idle", %{worker: pid} do
      # Setup: pause, queue commands, then resume
      {:ok, paused_state} = Worker.manage(pid, :pause)

      {:ok, state_with_pending} =
        Worker.process_act(%{command: :move, location: :kitchen}, paused_state)

      {:ok, state_with_more} =
        Worker.process_act(%{command: :move, location: :living_room}, state_with_pending)

      assert :queue.len(state_with_more.pending) == 2
      processed_state = Worker.process_pending_commands(%{state_with_more | status: :idle})
      assert :queue.len(processed_state.pending) == 0
      assert processed_state.agent.location == :living_room
    end

    test "skips processing when not idle", %{worker: pid} do
      state = :sys.get_state(pid)
      paused_state = %{state | status: :paused}
      {:ok, state_with_pending} = Worker.process_act(%{command: :move}, paused_state)

      assert state_with_pending == Worker.process_pending_commands(state_with_pending)
    end
  end
end
