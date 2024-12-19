defmodule Jido.Agent.WorkerTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Agent.Worker
  alias JidoTest.SimpleAgent

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, _} = start_supervised({Registry, keys: :unique, name: Jido.AgentRegistry})
    agent = SimpleAgent.new("test_agent")
    %{agent: agent}
  end

  describe "start_link/1" do
    test "starts worker with valid agent and pubsub", %{agent: agent} do
      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      assert Process.alive?(pid)
      assert [{^pid, nil}] = Registry.lookup(Jido.AgentRegistry, "test_agent")
    end

    test "starts worker with module agent", %{agent: _agent} do
      {:ok, pid} = Worker.start_link(agent: SimpleAgent, pubsub: TestPubSub)
      assert Process.alive?(pid)
      state = :sys.get_state(pid)
      assert state.agent.__struct__ == SimpleAgent
    end

    test "starts worker with custom topic", %{agent: agent} do
      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub, topic: "custom.topic")
      state = :sys.get_state(pid)
      assert state.topic == "custom.topic"
    end

    test "starts worker with custom name", %{agent: agent} do
      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub, name: "custom_name")
      assert [{^pid, nil}] = Registry.lookup(Jido.AgentRegistry, "custom_name")
    end

    test "fails to start with missing pubsub", %{agent: agent} do
      assert_raise KeyError, ~r/key :pubsub not found/, fn ->
        Worker.start_link(agent: agent)
      end
    end

    test "fails with duplicate registration", %{agent: agent} do
      {:ok, _pid1} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      assert {:error, {:already_started, _}} = Worker.start_link(agent: agent, pubsub: TestPubSub)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec", %{agent: agent} do
      spec = Worker.child_spec(agent: agent, pubsub: TestPubSub)
      assert spec.id == Worker
      assert spec.start == {Worker, :start_link, [[agent: agent, pubsub: TestPubSub]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end

    test "allows custom id", %{agent: agent} do
      spec = Worker.child_spec(agent: agent, pubsub: TestPubSub, id: :custom_id)
      assert spec.id == :custom_id
    end
  end

  describe "act/2" do
    setup %{agent: agent} do
      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      %{worker: pid}
    end

    test "sends act command to worker", %{worker: pid} do
      assert :ok = Worker.act(pid, %{command: :move, destination: :kitchen})
      state = :sys.get_state(pid)
      assert state.agent.location == :kitchen
    end

    test "handles invalid action parameters", %{worker: pid} do
      # Missing destination
      assert :ok = Worker.act(pid, %{command: :move})
      state = :sys.get_state(pid)
      # Location shouldn't change
      assert state.agent.location == :home
    end

    test "handles concurrent actions", %{worker: pid} do
      tasks =
        for dest <- [:kitchen, :living_room, :bedroom] do
          Task.async(fn -> Worker.act(pid, %{command: :move, destination: dest}) end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == :ok))

      # Last action should win
      state = :sys.get_state(pid)
      assert state.agent.location in [:kitchen, :living_room, :bedroom]
    end
  end

  describe "manage/3" do
    setup %{agent: agent} do
      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub)
      %{worker: pid}
    end

    test "pauses worker", %{worker: pid} do
      {:ok, running_state} = Worker.manage(pid, :resume)
      assert running_state.status == :running

      {:ok, state} = Worker.manage(pid, :pause)
      assert state.status == :paused
    end

    test "resumes worker", %{worker: pid} do
      {:ok, running_state} = Worker.manage(pid, :resume)
      assert running_state.status == :running

      {:ok, paused_state} = Worker.manage(pid, :pause)
      assert paused_state.status == :paused

      {:ok, state} = Worker.manage(pid, :resume)
      assert state.status == :running
    end

    test "handles invalid state transitions", %{worker: pid} do
      # Try to pause when already idle
      {:error, {:invalid_state, :idle}} = Worker.manage(pid, :pause)

      # Try to resume when already running
      {:ok, _} = Worker.manage(pid, :resume)
      {:error, {:invalid_state, :running}} = Worker.manage(pid, :resume)
    end

    test "resets worker", %{worker: pid} do
      # Queue some commands
      Worker.act(pid, %{command: :move, destination: :kitchen})
      Worker.act(pid, %{command: :move, destination: :living_room})

      {:ok, state} = Worker.manage(pid, :reset)
      assert state.status == :idle
      assert :queue.len(state.pending) == 0
    end

    test "handles state transitions during pending commands", %{worker: pid} do
      # Queue commands while paused
      {:ok, _} = Worker.manage(pid, :resume)
      {:ok, _} = Worker.manage(pid, :pause)

      Worker.act(pid, %{command: :move, destination: :kitchen})
      Worker.act(pid, %{command: :move, destination: :living_room})

      {:ok, state} = Worker.manage(pid, :resume)
      assert state.status == :running

      # Wait for commands to process
      :timer.sleep(100)
      final_state = :sys.get_state(pid)
      assert final_state.agent.location == :living_room
    end

    test "returns error for invalid command", %{worker: pid} do
      assert {:error, :invalid_command} = Worker.manage(pid, :invalid_command)
    end
  end

  describe "pubsub and events" do
    setup %{agent: agent} do
      topic = "test.topic"
      {:ok, pid} = Worker.start_link(agent: agent, pubsub: TestPubSub, topic: topic)
      Phoenix.PubSub.subscribe(TestPubSub, topic)
      %{worker: pid, topic: topic}
    end

    test "emits events for state transitions", %{worker: pid} do
      {:ok, _} = Worker.manage(pid, :resume)
      assert_receive %Signal{type: "jido.agent.state_changed", data: %{from: :idle, to: :running}}

      {:ok, _} = Worker.manage(pid, :pause)

      assert_receive %Signal{
        type: "jido.agent.state_changed",
        data: %{from: :running, to: :paused}
      }
    end

    test "emits events for completed actions", %{worker: pid} do
      Worker.act(pid, %{command: :move, destination: :kitchen})
      assert_receive %Signal{type: "jido.agent.act_completed"}, 1000
    end

    test "handles malformed signals", %{worker: pid, topic: topic} do
      # Send malformed signal directly
      Phoenix.PubSub.broadcast(TestPubSub, topic, %{invalid: "signal"})

      # Worker should still be alive and functioning
      assert Process.alive?(pid)
      assert :ok = Worker.act(pid, %{command: :move, destination: :kitchen})
    end
  end

  describe "max queue size" do
    setup %{agent: agent} do
      max_queue_size = 2
      topic = "test.topic"

      {:ok, pid} =
        Worker.start_link(
          agent: agent,
          pubsub: TestPubSub,
          topic: topic,
          max_queue_size: max_queue_size
        )

      Phoenix.PubSub.subscribe(TestPubSub, topic)

      # First resume to get to running state, then pause to force command queueing
      {:ok, _} = Worker.manage(pid, :resume)
      {:ok, _} = Worker.manage(pid, :pause)

      %{worker: pid, max_queue_size: max_queue_size}
    end

    test "accepts commands up to max queue size", %{worker: pid, max_queue_size: max_size} do
      # Fill queue to capacity
      for i <- 1..max_size do
        assert :ok = Worker.act(pid, %{command: :move, destination: "loc_#{i}"})
      end

      # Verify no overflow events were emitted
      refute_receive %Signal{type: "jido.agent.queue_overflow"}
    end

    test "drops commands when queue is full", %{worker: pid, max_queue_size: max_size} do
      # Fill queue to capacity
      for i <- 1..max_size do
        assert :ok = Worker.act(pid, %{command: :move, destination: "loc_#{i}"})
      end

      # Send one more command that should be dropped
      overflow_command = %{command: :move, destination: :overflow_location}
      assert :ok = Worker.act(pid, overflow_command)

      # Verify overflow event was emitted with correct data
      assert_receive %Signal{
        type: "jido.agent.queue_overflow",
        data: %{
          queue_size: ^max_size,
          max_size: ^max_size,
          dropped_command: {:act, ^overflow_command}
        }
      }
    end

    test "processes queued commands after resume", %{worker: pid, max_queue_size: max_size} do
      # Queue up commands - using simple move commands
      commands =
        for _i <- 1..max_size do
          %{command: :move, destination: :kitchen}
        end

      Enum.each(commands, &Worker.act(pid, &1))

      # Resume worker and wait for state change
      {:ok, _} = Worker.manage(pid, :resume)
      assert_receive %Signal{type: "jido.agent.state_changed", data: %{to: :running}}

      # Wait for either completion or failure signals
      for _ <- 1..max_size do
        receive do
          %Signal{type: "jido.agent.act_completed"} -> :ok
          %Signal{type: "jido.agent.act_failed"} -> :ok
        after
          1000 -> flunk("Command processing timeout")
        end
      end

      # Verify the state has changed in some way
      state = :sys.get_state(pid)
      refute state.agent.location == :home
    end

    test "handles custom max queue size", %{agent: _agent} do
      custom_size = 5
      # Create a new agent with a unique ID
      agent = SimpleAgent.new("test_agent_custom_queue")

      {:ok, pid} =
        Worker.start_link(
          agent: agent,
          pubsub: TestPubSub,
          topic: "test.topic",
          max_queue_size: custom_size
        )

      # First resume to get to running state, then pause to force command queueing
      {:ok, _} = Worker.manage(pid, :resume)
      {:ok, _} = Worker.manage(pid, :pause)

      # Fill queue to custom capacity
      for i <- 1..custom_size do
        assert :ok = Worker.act(pid, %{command: :move, destination: "loc_#{i}"})
      end

      # Verify next command is dropped
      overflow_command = %{command: :move, destination: :overflow_location}
      assert :ok = Worker.act(pid, overflow_command)

      assert_receive %Signal{
        type: "jido.agent.queue_overflow",
        data: %{
          queue_size: ^custom_size,
          max_size: ^custom_size,
          dropped_command: {:act, ^overflow_command}
        }
      }
    end

    test "uses default max queue size when not specified", %{agent: _agent} do
      # Create a new agent with a unique ID
      agent = SimpleAgent.new("test_agent_default_queue")

      {:ok, pid} =
        Worker.start_link(
          agent: agent,
          pubsub: TestPubSub,
          topic: "test.topic"
        )

      # First resume to get to running state to match other tests
      {:ok, _} = Worker.manage(pid, :resume)

      state = :sys.get_state(pid)
      assert state.max_queue_size == 10_000
    end
  end
end
