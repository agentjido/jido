defmodule Jido.Agent.BusSpyIntegrationTest do
  use ExUnit.Case, async: true
  use JidoTest.AgentCase

  describe "bus spy with cross-process signals" do
    test "spy captures signals crossing process boundaries with trace context" do
      # Start the bus spy to observe cross-process signals
      spy = start_bus_spy()

      # Set up cross-process agents
      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      # Send a root signal that will trigger cross-process communication
      send_signal_sync(producer, "root", %{test_data: "cross-process-spy-test"})

      # Wait for cross-process completion
      wait_for_cross_process_completion([consumer])

      # Verify signals crossed the bus and were observed by the spy
      assert_bus_signal_observed(spy, "child.event")

      # Get the specific signal that crossed the bus
      child_signals = get_spy_signals(spy, "child.event")
      assert length(child_signals) >= 1

      [signal_event] = child_signals

      # Verify signal content
      assert signal_event.signal.type == "child.event"
      assert signal_event.signal.data.test_data == "cross-process-spy-test"

      # Verify trace context was preserved across process boundaries
      assert signal_event.signal.trace_context != nil
      assert signal_event.signal.trace_context.trace_id != nil

      # Verify the consumer received the signal with the same trace context
      received_signals = get_received_signals(consumer)
      assert length(received_signals) >= 1

      [received_signal] = received_signals
      assert received_signal.trace_context.trace_id == signal_event.signal.trace_context.trace_id

      # Verify bus metadata was captured
      assert signal_event.bus_name != nil
      assert signal_event.subscription_id != nil
      assert signal_event.subscription_path != nil
      assert signal_event.event == :before_dispatch
    end

    test "spy can wait for specific signals across process boundaries" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      # Start async task to send signal after delay
      Task.start(fn ->
        Process.sleep(100)
        send_signal_sync(producer, "root", %{async_test: true})
      end)

      # Wait for the cross-process signal to appear on the bus
      assert {:ok, signal_event} = wait_for_bus_signal(spy, "child.event", timeout: 2000)
      assert signal_event.signal.data.async_test == true

      # Verify the signal reached the consumer
      wait_for_cross_process_completion([consumer])
      received_signals = get_received_signals(consumer)
      assert length(received_signals) >= 1
    end

    test "spy captures multiple signals in complex cross-process scenarios" do
      spy = start_bus_spy()

      # Set up multiple producer-consumer pairs
      %{producer: producer1, consumer: consumer1} = setup_cross_process_agents()
      %{producer: producer2, consumer: consumer2} = setup_cross_process_agents()

      # Send signals from both producers
      send_signal_sync(producer1, "root", %{producer: 1, data: "first"})
      send_signal_sync(producer2, "root", %{producer: 2, data: "second"})

      # Wait for all cross-process completion
      wait_for_cross_process_completion([consumer1, consumer2])

      # Verify spy captured both signals
      child_signals = get_spy_signals(spy, "child.event")
      assert length(child_signals) >= 2

      # Verify each signal has unique trace context
      trace_ids = Enum.map(child_signals, & &1.signal.trace_context.trace_id)
      assert length(Enum.uniq(trace_ids)) == length(trace_ids)

      # Verify both consumers received their respective signals
      received1 = get_received_signals(consumer1)
      received2 = get_received_signals(consumer2)
      assert length(received1) >= 1
      assert length(received2) >= 1
    end

    test "spy pattern matching works with cross-process signals" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      # Send multiple root signals to generate different child events
      send_signal_sync(producer, "root", %{event_type: "user_action"})
      send_signal_sync(producer, "root", %{event_type: "system_action"})

      wait_for_cross_process_completion([consumer])

      # Test different pattern matches
      all_signals = get_spy_signals(spy, "*")
      child_signals = get_spy_signals(spy, "child.*")
      exact_signals = get_spy_signals(spy, "child.event")

      assert length(all_signals) >= 2
      assert length(child_signals) >= 2
      assert length(exact_signals) >= 2
      # All are "child.event"
      assert length(child_signals) == length(exact_signals)
    end

    test "spy observes dispatch results and errors" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{test_dispatch_result: true})
      wait_for_cross_process_completion([consumer])

      # Get all spy events (before and after dispatch)
      all_events = get_spy_signals(spy)

      # Should have both before_dispatch and after_dispatch events
      before_events = Enum.filter(all_events, &(&1.event == :before_dispatch))
      after_events = Enum.filter(all_events, &(&1.event == :after_dispatch))

      assert length(before_events) >= 1
      assert length(after_events) >= 1

      # Verify after_dispatch events have dispatch results
      for after_event <- after_events do
        assert after_event.dispatch_result != nil
      end
    end
  end

  describe "bus spy trace correlation" do
    test "verify exact signal that traveled across process boundary" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      # Send with specific trace context data
      original_trace_data = %{
        operation: "cross_process_test",
        user_id: "user_123",
        request_id: "req_abc"
      }

      send_signal_sync(producer, "root", %{trace_data: original_trace_data})
      wait_for_cross_process_completion([consumer])

      # Get the bus signal and verify trace correlation
      [bus_signal] = get_spy_signals(spy, "child.event")

      # The signal data should contain our original trace data
      assert bus_signal.signal.data.trace_data == original_trace_data

      # The trace context should be preserved
      assert bus_signal.signal.trace_context != nil

      # Verify the consumer received the exact same signal
      [received_signal] = get_received_signals(consumer)
      assert received_signal.data.trace_data == original_trace_data
      assert received_signal.trace_context.trace_id == bus_signal.signal.trace_context.trace_id
    end
  end
end
