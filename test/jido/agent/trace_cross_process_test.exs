defmodule Jido.Agent.TraceCrossProcessTest do
  # async: false because these tests use a shared :test_bus name
  use JidoTest.Case, async: false
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

  describe "Cross-Process Trace Correlation" do
    test "trace IDs flow between separate agent processes" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{test_data: "trace_flow"})

      wait_for_cross_process_completion([producer, consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      dispatched_signals = get_spy_signals(spy)
      assert length(dispatched_signals) >= 1

      assert_trace_propagation(producer, consumer)
    end

    test "parent-child relationships maintained across process boundaries" do
      _spy = start_bus_spy()
      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{chain_test: "parent_child"})
      wait_for_cross_process_completion([producer, consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      emitted = get_emitted_signals(producer)
      received = get_received_signals(consumer)

      assert length(emitted) == 1
      assert length(received) == 1

      emitted_signal = List.first(emitted)
      received_signal = List.first(received)

      assert emitted_signal.type == "child.event"
      assert received_signal.signal_data != nil

      consumer_trace = get_latest_trace_context(consumer)
      assert consumer_trace != nil
      assert is_binary(consumer_trace[:trace_id])
    end

    test "ProducerAgent stores emitted signal data in state" do
      # This tests the current implementation: ProducerAgent stores signal
      # data in state when processing "root" signals
      producer = spawn_producer_agent()

      send_signal_sync(producer, "root", %{isolation_test: "separate_contexts"})

      emitted = get_emitted_signals(producer)
      assert length(emitted) == 1

      assert emitted |> List.first() |> Map.get(:type) == "child.event"
    end

    test "signal bus properly carries trace context using BusSpy" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{bus_test: "trace_preservation"})
      wait_for_cross_process_completion([producer, consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      dispatched_signals = get_spy_signals(spy)
      assert length(dispatched_signals) >= 1

      for signal_event <- dispatched_signals do
        assert signal_event.signal != nil
        assert signal_event.signal_type != nil
        assert signal_event.signal_id != nil
      end

      assert_trace_propagation(producer, consumer)
    end

    test "full trace chain verification: Root → Child → Grandchild" do
      spy = start_bus_spy()

      %{producer: producer, consumer: consumer} = setup_cross_process_agents()

      send_signal_sync(producer, "root", %{chain_operation: "full_trace"})
      wait_for_cross_process_completion([producer, consumer])
      wait_for_received_signals(consumer, 1, timeout: 2000)

      emitted_signals = get_emitted_signals(producer)
      received_signals = get_received_signals(consumer)

      assert length(emitted_signals) == 1, "Producer should emit exactly one child signal"
      assert length(received_signals) == 1, "Consumer should receive exactly one signal"

      child_signal = List.first(emitted_signals)
      received_signal = List.first(received_signals)

      assert child_signal.type == "child.event"
      assert received_signal.signal_data != nil

      consumer_trace = get_latest_trace_context(consumer)
      assert consumer_trace != nil, "Consumer should have trace context"
      assert is_binary(consumer_trace[:trace_id]), "Consumer should have valid trace ID"

      bus_signals = get_spy_signals(spy)
      assert length(bus_signals) >= 1, "Bus spy should capture signal dispatch events"
    end

    test "multiple producer agents work independently" do
      # Tests that multiple producer agents can process signals independently
      # without cross-process signal flow
      initial_producer = spawn_producer_agent()
      send_signal_sync(initial_producer, "root", %{restart_test: "before"})

      before_signals = get_emitted_signals(initial_producer)
      assert length(before_signals) == 1

      new_producer = spawn_producer_agent()
      send_signal_sync(new_producer, "root", %{restart_test: "after"})

      after_signals = get_emitted_signals(new_producer)
      assert length(after_signals) == 1

      before_signal = List.first(before_signals)
      after_signal = List.first(after_signals)

      assert before_signal.data.root_data.restart_test == "before"
      assert after_signal.data.root_data.restart_test == "after"
    end

    test "concurrent trace propagation across multiple agent chains" do
      spy = start_bus_spy()

      # Set up two independent producer-consumer chains sharing the same bus
      %{producer: producer1, consumer: consumer1, bus: bus} = setup_cross_process_agents()
      %{producer: producer2, consumer: consumer2} = setup_cross_process_agents(bus: bus)

      send_signal_sync(producer1, "root", %{chain: 1, concurrent_test: "chain_1"})
      send_signal_sync(producer2, "root", %{chain: 2, concurrent_test: "chain_2"})

      wait_for_cross_process_completion([producer1, consumer1, producer2, consumer2])

      chain1_emitted = get_emitted_signals(producer1)
      chain2_emitted = get_emitted_signals(producer2)

      assert length(chain1_emitted) == 1
      assert length(chain2_emitted) == 1

      chain1_data = List.first(chain1_emitted).data
      chain2_data = List.first(chain2_emitted).data

      assert chain1_data.root_data.chain == 1
      assert chain2_data.root_data.chain == 2

      # Both consumers receive signals from the shared bus (all child.event signals)
      # Note: consumers may receive each other's signals since they both subscribe to child.event
      all_bus_signals = get_spy_signals(spy)
      assert length(all_bus_signals) >= 2
    end

    test "Oracle's detailed scenario: Agent-A → Signal Bus → Agent-B" do
      spy = start_bus_spy()

      %{producer: agent_a, consumer: agent_b} = setup_cross_process_agents()

      send_signal_sync(agent_a, "root", %{oracle_scenario: true, trace_data: "T"})

      wait_for_cross_process_completion([agent_a, agent_b])
      wait_for_received_signals(agent_b, 1, timeout: 2000)

      emitted_by_a = get_emitted_signals(agent_a)
      assert length(emitted_by_a) == 1

      child_signal = List.first(emitted_by_a)
      assert child_signal.type == "child.event"

      received_by_b = get_received_signals(agent_b)
      assert length(received_by_b) == 1

      received_signal = List.first(received_by_b)
      assert received_signal.signal_data != nil

      b_trace_context = get_latest_trace_context(agent_b)
      assert b_trace_context != nil, "Agent-B should have trace context from received signal"

      bus_events = get_spy_signals(spy, "child.event")
      assert length(bus_events) >= 1, "Bus should have captured child.event signal"

      signal_event = List.first(bus_events)
      assert signal_event.signal_type == "child.event"
      assert signal_event.signal != nil

      assert_trace_propagation(agent_a, agent_b)
    end
  end
end
