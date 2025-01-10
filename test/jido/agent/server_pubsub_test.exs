defmodule JidoTest.Agent.Server.PubSubTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Server.{PubSub, State, Signal}
  alias Jido.Signal, as: BaseSignal

  setup do
    test_pid = self()
    topic = "test.topic"
    {:ok, _} = start_supervised({Phoenix.PubSub, name: TestPubSub})

    state = %State{
      agent: %{id: "test-agent"},
      pubsub: TestPubSub,
      topic: topic,
      status: :idle
    }

    {:ok, state: state, pubsub: TestPubSub, topic: topic, test_pid: test_pid}
  end

  describe "topic generation" do
    test "generates correct topic format" do
      topic = PubSub.generate_topic("test-123")
      assert topic == "jido.agent.test-123"
    end

    test "handles special characters in agent ID" do
      topic = PubSub.generate_topic("test/agent@123")
      assert topic == "jido.agent.test/agent@123"
    end
  end

  describe "event emission" do
    test "emits event with correct signal format", %{state: state, topic: topic} do
      {:ok, state} = PubSub.subscribe(state, topic)
      event_type = Signal.transition_succeeded()
      payload = %{from: :idle, to: :running}

      :ok = PubSub.emit_event(state, event_type, payload)

      assert_receive %BaseSignal{
        type: ^event_type,
        source: "jido",
        subject: "test-agent",
        data: ^payload
      }
    end

    test "includes correct metadata in emitted events", %{state: state, topic: topic} do
      {:ok, state} = PubSub.subscribe(state, topic)
      event_type = Signal.transition_succeeded()
      :ok = PubSub.emit_event(state, event_type, %{from: :idle, to: :running})

      assert_receive %BaseSignal{data: %{from: :idle, to: :running}}
    end

    test "handles empty payload", %{state: state, topic: topic} do
      {:ok, state} = PubSub.subscribe(state, topic)
      event_type = Signal.queue_cleared()
      :ok = PubSub.emit_event(state, event_type, %{})

      assert_receive %BaseSignal{
        type: ^event_type,
        data: %{}
      }
    end

    test "handles complex nested payloads", %{state: state, topic: topic} do
      {:ok, state} = PubSub.subscribe(state, topic)
      event_type = Signal.process_started()

      payload = %{
        nested: %{
          array: [1, 2, 3],
          map: %{key: "value"}
        },
        list: ["a", "b", "c"]
      }

      :ok = PubSub.emit_event(state, event_type, payload)

      assert_receive %BaseSignal{
        type: ^event_type,
        data: ^payload
      }
    end
  end

  describe "subscription" do
    test "subscribes to topic successfully", %{state: state, topic: topic} do
      assert {:ok, state} = PubSub.subscribe(state, topic)

      # Test subscription by emitting and receiving an event
      event_type = Signal.process_started()
      :ok = PubSub.emit_event(state, event_type, %{value: true})
      assert_receive %BaseSignal{type: ^event_type}
    end

    test "can subscribe multiple times to same topic", %{state: state, topic: topic} do
      assert {:ok, state} = PubSub.subscribe(state, topic)
      assert {:ok, _state} = PubSub.subscribe(state, topic)
    end

    test "receives all events after subscribing", %{state: state, topic: topic} do
      assert {:ok, state} = PubSub.subscribe(state, topic)

      event1 = Signal.process_started()
      event2 = Signal.process_terminated()
      event3 = Signal.transition_succeeded()

      :ok = PubSub.emit_event(state, event1, %{id: 1})
      :ok = PubSub.emit_event(state, event2, %{id: 2})
      :ok = PubSub.emit_event(state, event3, %{id: 3})

      assert_receive %BaseSignal{type: ^event1}
      assert_receive %BaseSignal{type: ^event2}
      assert_receive %BaseSignal{type: ^event3}
    end

    test "tracks subscriptions in state", %{state: state} do
      # Initial state should have no subscriptions
      assert state.subscriptions == []

      # After subscribing, topic should be in subscriptions
      {:ok, state_with_sub} = PubSub.subscribe(state, "topic1")
      assert state_with_sub.subscriptions == ["topic1"]

      # Subscribing again should not duplicate the subscription
      {:ok, state_with_dupe} = PubSub.subscribe(state_with_sub, "topic1")
      assert state_with_dupe.subscriptions == ["topic1"]
    end
  end

  describe "unsubscription" do
    test "unsubscribes from topic successfully", %{state: state, topic: topic} do
      {:ok, state} = PubSub.subscribe(state, topic)
      assert {:ok, state} = PubSub.unsubscribe(state, topic)

      # Should not receive events after unsubscribing
      event_type = Signal.process_started()
      :ok = PubSub.emit_event(state, event_type, %{value: true})
      refute_receive %BaseSignal{type: ^event_type}
    end

    test "can unsubscribe when not subscribed", %{state: state, topic: topic} do
      assert {:ok, _state} = PubSub.unsubscribe(state, topic)
    end

    test "stops receiving events after unsubscribe", %{state: state, topic: topic} do
      {:ok, state} = PubSub.subscribe(state, topic)

      # Should receive event before unsubscribe
      before_event = Signal.process_started()
      :ok = PubSub.emit_event(state, before_event, %{})
      assert_receive %BaseSignal{type: ^before_event}

      {:ok, state} = PubSub.unsubscribe(state, topic)

      # Should not receive event after unsubscribe
      after_event = Signal.process_terminated()
      :ok = PubSub.emit_event(state, after_event, %{})
      refute_receive %BaseSignal{type: ^after_event}
    end

    test "removes topic from subscriptions in state", %{state: state, topic: topic} do
      # Subscribe first to add topic to subscriptions
      {:ok, state_with_sub} = PubSub.subscribe(state, topic)
      assert state_with_sub.subscriptions == [topic]

      # After unsubscribing, subscriptions should be empty
      {:ok, state_without_sub} = PubSub.unsubscribe(state_with_sub, topic)
      assert state_without_sub.subscriptions == []

      # Unsubscribing again should not change the empty subscriptions
      {:ok, state_without_dupe} = PubSub.unsubscribe(state_without_sub, topic)
      assert state_without_dupe.subscriptions == []
    end
  end
end
