defmodule Jido.Agent.WorkerProcessTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Agent.Worker
  alias Jido.Agent.Worker.State
  alias JidoTest.SimpleAgent

  setup do
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})
    {:ok, _} = start_supervised({Registry, keys: :unique, name: Jido.AgentRegistry})

    agent = SimpleAgent.new("test")

    base_state = %State{
      agent: agent,
      pubsub: TestPubSub,
      topic: "test_topic",
      status: :idle,
      pending: :queue.new()
    }

    {:ok, base_state: base_state}
  end

  describe "via_tuple/1" do
    test "returns registry tuple" do
      assert {:via, Registry, {Jido.AgentRegistry, "test"}} == Worker.via_tuple("test")
    end
  end

  describe "emit/3" do
    test "creates and broadcasts signal", %{base_state: state} do
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)
      payload = %{foo: "bar"}

      assert :ok = Worker.emit(state, "test_event", payload)

      # Verify signal was broadcast with correct format
      assert_receive %Signal{
        type: "jido.agent.test_event",
        source: "/agent/test",
        data: ^payload
      }
    end
  end

  describe "subscribe_to_topic/1" do
    test "subscribes to pubsub topic", %{base_state: state} do
      assert :ok = Worker.subscribe_to_topic(state)
    end
  end

  describe "queue_command/2" do
    test "adds command to pending queue", %{base_state: state} do
      command = {:act, %{command: :custom, message: "test"}}

      assert {:ok, new_state} = Worker.queue_command(state, command)
      assert :queue.len(new_state.pending) == 1

      {{:value, queued_command}, _} = :queue.out(new_state.pending)
      assert queued_command == command
    end
  end

  describe "validate_state/1" do
    test "validates state with valid inputs", %{base_state: state} do
      assert :ok = Worker.validate_state(state)
    end

    test "fails validation with nil pubsub", %{base_state: state} do
      state = %{state | pubsub: nil}
      assert {:error, "PubSub module is required"} = Worker.validate_state(state)
    end

    test "fails validation with nil agent", %{base_state: state} do
      state = %{state | agent: nil}
      assert {:error, "Agent is required"} = Worker.validate_state(state)
    end
  end

  describe "process_signal/2" do
    test "processes act signal", %{base_state: state} do
      # Verify we start at home
      assert state.agent.location == :home

      {:ok, signal} =
        Signal.new(%{
          type: "jido.agent.act",
          source: "/test",
          data: %{command: :move, destination: :kitchen}
        })

      assert {:ok, new_state} = Worker.process_signal(signal, state)
      assert new_state.status == :idle
      assert new_state.agent.location == :kitchen
    end

    test "processes manage signal", %{base_state: state} do
      state = %{state | status: :running}

      {:ok, signal} =
        Signal.new(%{
          type: "jido.agent.manage",
          source: "/test",
          data: %{command: :pause, args: nil}
        })

      assert {:ok, new_state} = Worker.process_signal(signal, state)
      assert new_state.status == :paused
    end

    test "ignores unknown signal type", %{base_state: state} do
      {:ok, signal} = Signal.new(%{type: "unknown", source: "/test", data: %{}})
      assert :ignore = Worker.process_signal(signal, state)
    end
  end

  describe "process_act/2" do
    test "executes action and updates agent state", %{base_state: state} do
      # Verify we start at home
      assert state.agent.location == :home

      attrs = %{command: :move, destination: :kitchen}
      assert {:ok, new_state} = Worker.process_act(attrs, state)
      assert new_state.status == :idle
      assert new_state.agent.location == :kitchen
    end

    test "queues action when paused", %{base_state: state} do
      state = %{state | status: :paused}
      attrs = %{command: :move, destination: :kitchen}

      assert {:ok, new_state} = Worker.process_act(attrs, state)
      assert :queue.len(new_state.pending) == 1
      assert new_state.status == :paused

      {{:value, {:act, queued_attrs}}, _} = :queue.out(new_state.pending)
      assert queued_attrs == attrs
    end

    test "fails for invalid state", %{base_state: state} do
      state = %{state | status: :planning}
      attrs = %{command: :move, destination: :kitchen}

      assert {:error, {:invalid_state, :planning}} = Worker.process_act(attrs, state)
    end
  end

  describe "process_manage/4" do
    test "pauses agent", %{base_state: state} do
      state = %{state | status: :running}
      assert {:ok, new_state} = Worker.process_manage(:pause, nil, nil, state)
      assert new_state.status == :paused
    end

    test "resumes paused agent", %{base_state: state} do
      state = %{state | status: :paused}
      assert {:ok, new_state} = Worker.process_manage(:resume, nil, nil, state)
      assert new_state.status == :running
    end

    test "resets agent state", %{base_state: state} do
      state = %{
        state
        | status: :paused,
          pending: :queue.from_list([{:act, %{command: :custom, message: "test"}}])
      }

      assert {:ok, new_state} = Worker.process_manage(:reset, nil, nil, state)
      assert new_state.status == :idle
      assert :queue.len(new_state.pending) == 0
    end

    test "returns error for invalid command", %{base_state: state} do
      assert {:error, :invalid_command} = Worker.process_manage(:invalid, nil, nil, state)
    end
  end

  describe "process_pending_commands/1" do
    test "processes all pending commands in order", %{base_state: state} do
      # Verify we start at home
      assert state.agent.location == :home

      commands = [
        {:act, %{command: :move, destination: :kitchen}},
        {:act, %{command: :move, destination: :living_room}}
      ]

      state = %{state | pending: :queue.from_list(commands)}
      processed_state = Worker.process_pending_commands(state)

      assert processed_state.status == :idle
      assert :queue.len(processed_state.pending) == 0
      assert processed_state.agent.location == :living_room
    end

    test "stops processing on error", %{base_state: state} do
      # Verify we start at home
      assert state.agent.location == :home

      # First command is valid, second will fail
      commands = [
        {:act, %{command: :move, destination: :kitchen}},
        {:act, %{invalid: "command"}}
      ]

      state = %{state | pending: :queue.from_list(commands)}
      processed_state = Worker.process_pending_commands(state)

      assert processed_state.status == :idle
      assert :queue.len(processed_state.pending) == 0
      assert processed_state.agent.location == :kitchen
    end

    test "skips processing when not idle", %{base_state: state} do
      state = %{
        state
        | status: :running,
          pending: :queue.from_list([{:act, %{command: :move, destination: :kitchen}}])
      }

      assert ^state = Worker.process_pending_commands(state)
    end
  end

  describe "execute_action/2" do
    test "updates agent state when executing move command", %{base_state: state} do
      # Verify we start at home
      assert state.agent.location == :home

      state = %{state | status: :running}
      attrs = %{command: :move, destination: :kitchen}

      assert {:ok, updated_agent} = Worker.execute_action(state, attrs)
      assert updated_agent.location == :kitchen
    end

    test "updates agent state when executing recharge command", %{base_state: state} do
      state = %{state | status: :running}
      state = put_in(state.agent.battery_level, 50)
      attrs = %{command: :recharge}

      assert {:ok, updated_agent} = Worker.execute_action(state, attrs)
      assert updated_agent.battery_level == 100
    end

    test "executes default action without changing state", %{base_state: state} do
      state = %{state | status: :running}
      initial_state = state.agent
      attrs = %{message: "test message"}

      assert {:ok, updated_agent} = Worker.execute_action(state, attrs)
      # Default action only logs messages and sleeps, no state changes
      assert updated_agent == initial_state
    end

    test "fails if not in running state", %{base_state: state} do
      attrs = %{command: :move, destination: :kitchen}
      assert {:error, {:invalid_state, :idle}} = Worker.execute_action(state, attrs)
    end
  end
end
