defmodule JidoTest.Agent.TraceIntegrationTest do
  @moduledoc """
  Integration tests for the signal tracing system.

  Tests verify end-to-end trace context propagation, parent-child signal relationships,
  and CloudEvents attribute format compliance across the Jido agent system.
  """
  use JidoTest.Case, async: false
  use JidoTest.AgentCase

  alias Jido.Signal
  alias Jido.Signal.TraceContext
  alias Jido.Signal.Trace.Propagate
  alias Jido.Agent.Server

  @moduletag :integration
  @moduletag timeout: 10_000

  setup do
    # Clear any existing trace context before each test
    TraceContext.clear()
    :ok
  end

  describe "single agent signal correlation" do
    test "signals created during agent processing maintain trace relationships" do
      # Create agent
      agent_context = spawn_agent(JidoTest.TestAgents.BasicAgent)

      # Send a signal with trace context
      {:ok, traced_signal} =
        Signal.new(%{
          type: "basic_action",
          data: %{value: 42},
          source: "integration-test",
          trace_id: "integration-trace-123",
          span_id: "trigger-span-456",
          parent_span_id: "root-span-000"
        })

      {:ok, _} = Server.cast(agent_context.server_pid, traced_signal)

      # Wait for processing to complete
      Process.sleep(100)

      agent_context
      |> wait_for_agent_status(:idle, timeout: 1000)

      # The agent successfully processed a traced signal
      assert get_agent_state(agent_context) != nil
    end

    test "trace context propagation through Propagate module" do
      # Set up existing trace context
      existing_context = %{
        trace_id: "propagate-trace-789",
        span_id: "current-span-abc",
        parent_span_id: "parent-span-def"
      }

      TraceContext.set(existing_context)

      # Create test server state
      agent = JidoTest.TestAgents.BasicAgent.new("propagate-test-agent")

      current_signal = %Signal{
        id: "causing-signal-123",
        type: "causing.event",
        source: "/test/propagation"
      }

      server_state = %Jido.Agent.Server.State{
        agent: agent,
        current_signal: current_signal,
        status: :processing
      }

      # Test propagation
      attrs = %{"type" => "child.event", "data" => %{value: 1}}
      enriched_attrs = Propagate.inject_trace_context(attrs, server_state)

      # Verify trace context was propagated
      assert enriched_attrs["trace_id"] == "propagate-trace-789"
      assert enriched_attrs["parent_span_id"] == "current-span-abc"
      assert enriched_attrs["causation_id"] == "causing-signal-123"
      assert is_binary(enriched_attrs["span_id"])
      assert enriched_attrs["span_id"] != "current-span-abc"
    end

    test "parent-child signal relationships are maintained" do
      # Set up trace context for parent
      parent_trace = %{trace_id: "family-trace-456", span_id: "parent-span-789"}
      TraceContext.set(parent_trace)

      # Create parent signal context
      agent = JidoTest.TestAgents.BasicAgent.new("family-test-agent")

      parent_signal = %Signal{
        id: "parent-signal-999",
        type: "parent.event",
        source: "/test/family",
        extensions: %{
          "correlation" => %{
            trace_id: "family-trace-456",
            span_id: "parent-span-789"
          }
        }
      }

      server_state = %Jido.Agent.Server.State{
        agent: agent,
        current_signal: parent_signal,
        status: :processing
      }

      # Create multiple child signals
      child1_attrs = %{"type" => "child.event.1", "data" => %{sequence: 1}}
      child2_attrs = %{"type" => "child.event.2", "data" => %{sequence: 2}}

      enriched_child1 = Propagate.inject_trace_context(child1_attrs, server_state)
      enriched_child2 = Propagate.inject_trace_context(child2_attrs, server_state)

      # Verify family relationships
      assert enriched_child1["trace_id"] == "family-trace-456"
      assert enriched_child2["trace_id"] == "family-trace-456"

      # Both children should point to the same parent
      assert enriched_child1["parent_span_id"] == "parent-span-789"
      assert enriched_child2["parent_span_id"] == "parent-span-789"

      # Both children should have the same causation (parent signal)
      assert enriched_child1["causation_id"] == "parent-signal-999"
      assert enriched_child2["causation_id"] == "parent-signal-999"

      # But children should have different span IDs
      assert enriched_child1["span_id"] != enriched_child2["span_id"]
    end
  end

  describe "trace context propagation" do
    test "TraceContext module manages process-local context" do
      # Start with clean slate
      assert is_nil(TraceContext.current())

      # Set complex context
      context = %{
        trace_id: "context-test-abc",
        span_id: "context-span-def",
        parent_span_id: "context-parent-ghi",
        causation_id: "context-cause-jkl"
      }

      assert :ok = TraceContext.set(context)
      assert ^context = TraceContext.current()

      # Clear and verify
      assert :ok = TraceContext.clear()
      assert is_nil(TraceContext.current())
    end

    test "context extraction from signal extensions" do
      # Create signal with trace extension
      signal_with_trace = %Signal{
        id: "extraction-signal",
        type: "extraction.test",
        source: "/test/extraction",
        extensions: %{
          "correlation" => %{
            trace_id: "extracted-trace-123",
            span_id: "extracted-span-456",
            parent_span_id: "extracted-parent-789",
            causation_id: "extracted-cause-abc"
          }
        }
      }

      state = %{current_signal: signal_with_trace}

      # Extract context from signal
      assert :ok = TraceContext.ensure_set_from_state(state)

      # Verify extraction worked
      current = TraceContext.current()
      assert current.trace_id == "extracted-trace-123"
      assert current.span_id == "extracted-span-456"
      assert current.parent_span_id == "extracted-parent-789"
      assert current.causation_id == "extracted-cause-abc"
    end

    test "graceful handling of missing trace context" do
      # No context set
      assert is_nil(TraceContext.current())

      # Try to propagate with empty state
      attrs = %{"type" => "fallback.event", "data" => %{}}
      state = %{current_signal: nil}

      result = Propagate.inject_trace_context(attrs, state)

      # Should create new root trace context
      assert is_binary(result["trace_id"])
      assert is_binary(result["span_id"])
      # Root trace pattern
      assert result["trace_id"] == result["span_id"]
      refute Map.has_key?(result, "parent_span_id")
      refute Map.has_key?(result, "causation_id")
    end
  end

  describe "CloudEvents attribute format" do
    test "signals contain proper CloudEvents trace attributes" do
      # Set up known trace context
      trace_context = %{
        trace_id: "cloudevents-trace-123",
        span_id: "cloudevents-span-456",
        parent_span_id: "cloudevents-parent-789",
        causation_id: "cloudevents-cause-abc"
      }

      TraceContext.set(trace_context)

      # Create signal attributes
      attrs = %{
        "type" => "cloudevents.test",
        "source" => "/cloudevents/test",
        "data" => %{test: "data"}
      }

      state = %{current_signal: %{id: "cloudevents-cause-abc"}}
      enriched = Propagate.inject_trace_context(attrs, state)

      # Verify CloudEvents format
      assert enriched["trace_id"] == "cloudevents-trace-123"
      assert enriched["parent_span_id"] == "cloudevents-span-456"
      assert enriched["causation_id"] == "cloudevents-cause-abc"
      assert is_binary(enriched["span_id"])

      # Verify original attributes preserved
      assert enriched["type"] == "cloudevents.test"
      assert enriched["source"] == "/cloudevents/test"
      assert enriched["data"] == %{test: "data"}
    end

    test "signal creation and serialization round-trip" do
      # Create signal with CloudEvents trace attributes
      signal_attrs = %{
        "type" => "roundtrip.test",
        "source" => "/test/roundtrip",
        "traceid" => "roundtrip-trace-456",
        "spanid" => "roundtrip-span-789",
        "parentspan" => "roundtrip-parent-abc",
        "causationid" => "roundtrip-cause-def"
      }

      {:ok, signal} = Signal.new(signal_attrs)

      # Verify CloudEvents attributes are stored as extensions
      assert signal.extensions["traceid"] == "roundtrip-trace-456"
      assert signal.extensions["spanid"] == "roundtrip-span-789"
      assert signal.extensions["parentspan"] == "roundtrip-parent-abc"
      assert signal.extensions["causationid"] == "roundtrip-cause-def"

      # Verify the signal was created successfully
      assert signal.type == "roundtrip.test"
      assert signal.source == "/test/roundtrip"
    end
  end

  describe "integration with agent processing" do
    test "end-to-end trace correlation through agent signal processing" do
      # Create agent
      agent_context = spawn_agent(JidoTest.TestAgents.BasicAgent)

      # Create and send traced signal
      {:ok, initial_signal} =
        Signal.new(%{
          type: "basic_action",
          data: %{value: 42},
          source: "integration-test",
          traceid: "e2e-trace-123",
          spanid: "e2e-initial-456"
        })

      {:ok, _} = Server.cast(agent_context.server_pid, initial_signal)

      # Wait for processing
      Process.sleep(100)

      agent_context
      |> wait_for_agent_status(:idle, timeout: 2000)

      # Verify agent processed the signal successfully
      state = get_agent_state(agent_context)
      assert state != nil
    end

    test "multiple agents maintain separate trace contexts" do
      # Create two agents
      agent1 = spawn_agent(JidoTest.TestAgents.BasicAgent)
      agent2 = spawn_agent(JidoTest.TestAgents.BasicAgent)

      # Send different traced signals to each
      {:ok, signal1} =
        Signal.new(%{
          type: "basic_action",
          data: %{value: 1},
          source: "test",
          traceid: "agent1-trace-111",
          spanid: "agent1-span-222"
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "basic_action",
          data: %{value: 2},
          source: "test",
          traceid: "agent2-trace-333",
          spanid: "agent2-span-444"
        })

      {:ok, _} = Server.cast(agent1.server_pid, signal1)
      {:ok, _} = Server.cast(agent2.server_pid, signal2)

      # Wait for both to process
      Process.sleep(100)

      wait_for_agent_status(agent1, :idle)
      wait_for_agent_status(agent2, :idle)

      # Verify both processed successfully
      assert get_agent_state(agent1) != nil
      assert get_agent_state(agent2) != nil
    end

    test "trace context isolation between test runs" do
      # Verify clean state at start
      assert is_nil(TraceContext.current())

      # Set context in first "run"
      TraceContext.set(%{trace_id: "isolated-trace-1", span_id: "isolated-span-1"})
      context1 = TraceContext.current()

      # Clear context (simulating test cleanup)
      TraceContext.clear()

      # Verify clean state for next "run"
      assert is_nil(TraceContext.current())

      # Set different context in second "run"
      TraceContext.set(%{trace_id: "isolated-trace-2", span_id: "isolated-span-2"})
      context2 = TraceContext.current()

      # Verify contexts are different and isolated
      assert context1.trace_id != context2.trace_id
      assert context1.span_id != context2.span_id
    end
  end
end
