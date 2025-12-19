defmodule JidoTest.Signal.Trace.PropagateTest do
  use JidoTest.Case, async: false
  use Mimic

  alias Jido.Signal.TraceContext
  alias Jido.Signal.Trace.Propagate
  alias Jido.Signal.ID

  setup do
    # Clear any existing trace context before each test
    TraceContext.clear()
    :ok
  end

  describe "inject_trace_context/2" do
    test "injects trace context from process context" do
      # Set up existing trace context
      existing_context = %{
        trace_id: "existing-trace-123",
        span_id: "current-span-456",
        parent_span_id: "parent-span-789"
      }

      TraceContext.set(existing_context)

      # Mock ID generation for predictable span ID
      expect(ID, :generate!, fn -> "new-span-abc" end)

      attrs = %{"type" => "user.created", "subject" => "user123"}
      state = %{current_signal: %{id: "signal-parent-123"}}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["type"] == "user.created"
      assert result["subject"] == "user123"
      assert result["trace_id"] == "existing-trace-123"
      assert result["span_id"] == "new-span-abc"
      assert result["parent_span_id"] == "current-span-456"
      assert result["causation_id"] == "signal-parent-123"
    end

    test "generates new span_id while preserving trace_id and parent_span_id" do
      existing_context = %{
        trace_id: "trace-xyz",
        span_id: "span-123",
        parent_span_id: "parent-456"
      }

      TraceContext.set(existing_context)

      expect(ID, :generate!, fn -> "generated-span-789" end)

      attrs = %{"type" => "workflow.step"}
      state = %{current_signal: %{id: "workflow-signal"}}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["trace_id"] == "trace-xyz"
      assert result["span_id"] == "generated-span-789"
      assert result["parent_span_id"] == "span-123"
      assert result["causation_id"] == "workflow-signal"
    end

    test "sets causation_id correctly from current signal" do
      existing_context = %{trace_id: "trace-123", span_id: "span-456"}
      TraceContext.set(existing_context)

      expect(ID, :generate!, fn -> "new-span" end)

      attrs = %{"type" => "event.triggered"}
      current_signal = %{id: "triggering-signal-789"}
      state = %{current_signal: current_signal}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["causation_id"] == "triggering-signal-789"
    end

    test "omits causation_id when current signal has no id" do
      existing_context = %{trace_id: "trace-123", span_id: "span-456"}
      TraceContext.set(existing_context)

      expect(ID, :generate!, fn -> "new-span" end)

      attrs = %{"type" => "event.triggered"}
      # No id field
      current_signal = %{other_field: "value"}
      state = %{current_signal: current_signal}

      result = Propagate.inject_trace_context(attrs, state)

      refute Map.has_key?(result, "causation_id")
    end

    test "omits causation_id when current signal is nil" do
      existing_context = %{trace_id: "trace-123", span_id: "span-456"}
      TraceContext.set(existing_context)

      expect(ID, :generate!, fn -> "new-span" end)

      attrs = %{"type" => "event.triggered"}
      state = %{current_signal: nil}

      result = Propagate.inject_trace_context(attrs, state)

      refute Map.has_key?(result, "causation_id")
    end

    test "extracts trace context from current signal when no process context exists" do
      # No process context set
      assert is_nil(TraceContext.current())

      signal = %{
        id: "signal-123",
        extensions: %{
          "correlation" => %{
            "trace_id" => "signal-trace-456",
            "span_id" => "signal-span-789",
            "parent_span_id" => "signal-parent-abc"
          }
        }
      }

      expect(ID, :generate!, fn -> "extracted-span-def" end)

      attrs = %{"type" => "extracted.event"}
      state = %{current_signal: signal}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["trace_id"] == "signal-trace-456"
      assert result["span_id"] == "extracted-span-def"
      assert result["parent_span_id"] == "signal-span-789"
      assert result["causation_id"] == "signal-123"
    end

    test "creates root context when no existing trace exists" do
      # No process context or signal trace
      assert is_nil(TraceContext.current())

      expect(ID, :generate!, fn -> "root-id-123" end)

      attrs = %{"type" => "root.event", "source" => "/system"}
      state = %{current_signal: nil}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["type"] == "root.event"
      assert result["source"] == "/system"
      assert result["trace_id"] == "root-id-123"
      assert result["span_id"] == "root-id-123"
      refute Map.has_key?(result, "parent_span_id")
      refute Map.has_key?(result, "causation_id")
    end

    test "creates root context when signal exists but has no trace extension" do
      signal = %{
        id: "signal-without-trace",
        extensions: %{"other_ext" => "data"}
      }

      expect(ID, :generate!, fn -> "fallback-root-789" end)

      attrs = %{"type" => "fallback.event"}
      state = %{current_signal: signal}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["trace_id"] == "fallback-root-789"
      assert result["span_id"] == "fallback-root-789"
      refute Map.has_key?(result, "parent_span_id")
      refute Map.has_key?(result, "causation_id")
    end

    test "handles empty state gracefully" do
      expect(ID, :generate!, fn -> "empty-state-id" end)

      attrs = %{"type" => "empty.state.event"}
      state = %{}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["trace_id"] == "empty-state-id"
      assert result["span_id"] == "empty-state-id"
    end

    test "preserves original attributes while adding trace data" do
      existing_context = %{trace_id: "preserve-trace", span_id: "preserve-span"}
      TraceContext.set(existing_context)

      expect(ID, :generate!, fn -> "preserve-new-span" end)

      attrs = %{
        "type" => "complex.event",
        "subject" => "user/456",
        "datacontenttype" => "application/json",
        "data" => %{"key" => "value"},
        "time" => "2023-01-01T12:00:00Z"
      }

      state = %{current_signal: nil}

      result = Propagate.inject_trace_context(attrs, state)

      # Original attributes preserved
      assert result["type"] == "complex.event"
      assert result["subject"] == "user/456"
      assert result["datacontenttype"] == "application/json"
      assert result["data"] == %{"key" => "value"}
      assert result["time"] == "2023-01-01T12:00:00Z"

      # Trace attributes added
      assert result["trace_id"] == "preserve-trace"
      assert result["span_id"] == "preserve-new-span"
    end

    test "handles trace context with atom keys from process context" do
      # Process context uses atom keys
      process_context = %{
        trace_id: "atom-trace-123",
        span_id: "atom-span-456",
        parent_span_id: "atom-parent-789"
      }

      TraceContext.set(process_context)
      expect(ID, :generate!, fn -> "atom-new-span" end)

      attrs = %{"type" => "atom.keys.test"}
      state = %{current_signal: %{id: "atom-signal"}}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["trace_id"] == "atom-trace-123"
      assert result["span_id"] == "atom-new-span"
      assert result["parent_span_id"] == "atom-span-456"
      assert result["causation_id"] == "atom-signal"
    end

    test "handles trace context with string keys from signal extension" do
      # Signal extension uses string keys
      signal = %{
        id: "string-signal",
        extensions: %{
          "correlation" => %{
            "trace_id" => "string-trace-123",
            "span_id" => "string-span-456"
          }
        }
      }

      expect(ID, :generate!, fn -> "string-new-span" end)

      attrs = %{"type" => "string.keys.test"}
      state = %{current_signal: signal}

      result = Propagate.inject_trace_context(attrs, state)

      assert result["trace_id"] == "string-trace-123"
      assert result["span_id"] == "string-new-span"
      assert result["parent_span_id"] == "string-span-456"
      assert result["causation_id"] == "string-signal"
    end
  end
end
