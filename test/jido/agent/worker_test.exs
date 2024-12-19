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
end
