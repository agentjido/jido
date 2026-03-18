defmodule Jido.Agent.BusSpyIntegrationTest do
  # async: false because these tests use a shared :test_bus name
  use ExUnit.Case, async: false
  use JidoTest.AgentCase

  # These tests are designed for Phase 3 of the jido_signal 1.1.0 migration.
  # They test cross-process signal flow via a signal bus, which requires:
  # 1. ProducerAgent to actually emit signals to a bus (not just store in state)
  # 2. ConsumerAgent to subscribe to the bus and receive signals
  # 3. BusSpy to observe signals crossing process boundaries
  #
  # Currently, the ProducerAgent only stores "emitted" signal data in its state
  # but doesn't actually dispatch signals to a bus. These tests are skipped
  # until the Emit directive and bus integration are implemented.
  #
  # See DEPS_UPDATE.md Phase 3 for migration details.

  describe "bus spy with cross-process signals" do
    test "spy captures signals crossing process boundaries with trace context" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{test_data: "cross-process-spy-test"})

      wait_for_cross_process_completion([consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      assert_bus_signal_observed(spy, "child.event")

      child_signals = get_spy_signals(spy, "child.event")
      assert length(child_signals) >= 1

      # Filter to get just the before_dispatch event
      signal_event = Enum.find(child_signals, &(&1.event == :before_dispatch))

      assert signal_event.signal.type == "child.event"
      assert signal_event.signal.data.root_data.test_data == "cross-process-spy-test"

      assert signal_event.signal.extensions["correlation"] != nil
      assert signal_event.signal.extensions["correlation"].trace_id != nil

      received_signals = get_received_signals(consumer)
      assert length(received_signals) >= 1

      [received_signal] = received_signals

      assert received_signal.trace_context.trace_id ==
               signal_event.signal.extensions["correlation"].trace_id

      assert signal_event.bus_name != nil
      assert signal_event.subscription_id != nil
      assert signal_event.subscription_path != nil
      assert signal_event.event == :before_dispatch
    end

    test "spy can wait for specific signals across process boundaries" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      # Use Task.async to ensure we wait for completion
      task =
        Task.async(fn ->
          Process.sleep(100)
          send_signal_sync(producer, "root", %{async_test: true})
        end)

      assert {:ok, signal_event} = wait_for_bus_signal(spy, "child.event", timeout: 2000)
      assert signal_event.signal.data.root_data.async_test == true

      # Wait for the task to complete first
      Task.await(task, 2000)

      # Wait for consumer to process the signal
      wait_for_cross_process_completion([consumer], timeout: 2000)
      wait_for_received_signals(consumer, 1, timeout: 2000)
      received_signals = get_received_signals(consumer)
      assert length(received_signals) >= 1
    end

    test "spy captures multiple signals in complex cross-process scenarios" do
      spy = start_bus_spy()

      # Send multiple signals to the same producer/consumer pair
      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{sequence: 1, data: "first"})
      send_signal_sync(producer, "root", %{sequence: 2, data: "second"})

      wait_for_cross_process_completion([consumer])
      wait_for_received_signals(consumer, 2, timeout: 2000)

      child_signals = get_spy_signals(spy, "child.event")
      assert length(child_signals) >= 2

      # Filter to unique signals (each signal has before/after events)
      before_events = Enum.filter(child_signals, &(&1.event == :before_dispatch))
      trace_ids = Enum.map(before_events, & &1.signal.extensions["correlation"].trace_id)
      assert length(Enum.uniq(trace_ids)) == length(trace_ids)

      received = get_received_signals(consumer)
      assert length(received) >= 2
    end

    test "spy pattern matching works with cross-process signals" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{event_type: "user_action"})
      send_signal_sync(producer, "root", %{event_type: "system_action"})

      wait_for_cross_process_completion([consumer])
      wait_for_received_signals(consumer, 2, timeout: 2000)

      all_signals = get_spy_signals(spy, "*")
      child_signals = get_spy_signals(spy, "child.*")
      exact_signals = get_spy_signals(spy, "child.event")

      assert length(all_signals) >= 2
      assert length(child_signals) >= 2
      assert length(exact_signals) >= 2
      assert length(child_signals) == length(exact_signals)
    end

    test "spy observes dispatch results and errors" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{test_dispatch_result: true})
      wait_for_cross_process_completion([consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      all_events = get_spy_signals(spy)

      before_events = Enum.filter(all_events, &(&1.event == :before_dispatch))
      after_events = Enum.filter(all_events, &(&1.event == :after_dispatch))

      assert length(before_events) >= 1
      assert length(after_events) >= 1

      for after_event <- after_events do
        assert after_event.dispatch_result != nil
      end
    end
  end

  describe "bus spy trace correlation" do
    test "verify exact signal that traveled across process boundary" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      original_trace_data = %{
        operation: "cross_process_test",
        user_id: "user_123",
        request_id: "req_abc"
      }

      send_signal_sync(producer, "root", %{trace_data: original_trace_data})
      wait_for_cross_process_completion([consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      # Filter to get just the before_dispatch event
      child_signals = get_spy_signals(spy, "child.event")
      bus_signal = Enum.find(child_signals, &(&1.event == :before_dispatch))

      assert bus_signal.signal.data.root_data.trace_data == original_trace_data

      assert bus_signal.signal.extensions["correlation"] != nil

      [received_signal] = get_received_signals(consumer)
      assert received_signal.signal_data.root_data.trace_data == original_trace_data

      assert received_signal.trace_context.trace_id ==
               bus_signal.signal.extensions["correlation"].trace_id
    end
  end
end
