defmodule JidoTest.Signal.TraceContextTest do
  use JidoTest.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.TraceContext

  setup do
    # Clear any existing trace context before each test
    TraceContext.clear()
    :ok
  end

  describe "set/1 and current/0" do
    test "set and retrieve trace context round-trip" do
      context = %{trace_id: "abc123", span_id: "def456"}

      assert :ok = TraceContext.set(context)
      assert ^context = TraceContext.current()
    end

    test "returns nil when no context is set" do
      assert is_nil(TraceContext.current())
    end

    test "overwrites existing context" do
      first_context = %{trace_id: "first", span_id: "span1"}
      second_context = %{trace_id: "second", span_id: "span2"}

      TraceContext.set(first_context)
      TraceContext.set(second_context)

      assert ^second_context = TraceContext.current()
    end

    test "handles complex context data" do
      context = %{
        trace_id: "trace123",
        span_id: "span456",
        parent_span_id: "parent789",
        causation_id: "signal-abc"
      }

      TraceContext.set(context)
      assert ^context = TraceContext.current()
    end
  end

  describe "clear/0" do
    test "clears existing trace context" do
      context = %{trace_id: "abc123", span_id: "def456"}
      TraceContext.set(context)

      assert :ok = TraceContext.clear()
      assert is_nil(TraceContext.current())
    end

    test "clearing when no context exists returns ok" do
      assert :ok = TraceContext.clear()
      assert is_nil(TraceContext.current())
    end
  end

  describe "ensure_set_from_state/1" do
    test "sets trace context from signal with trace extension" do
      signal = %Signal{
        id: "signal123",
        type: "test.event",
        source: "/test",
        extensions: %{
          "correlation" => %{
            trace_id: "trace123",
            span_id: "span456",
            parent_span_id: "parent789",
            causation_id: "cause-abc"
          }
        }
      }

      state = %{current_signal: signal}

      assert :ok = TraceContext.ensure_set_from_state(state)

      expected_context = %{
        trace_id: "trace123",
        span_id: "span456",
        parent_span_id: "parent789",
        causation_id: "cause-abc"
      }

      assert ^expected_context = TraceContext.current()
    end

    test "returns error when signal has no trace extension" do
      signal = %Signal{
        id: "signal123",
        type: "test.event",
        source: "/test",
        extensions: %{}
      }

      state = %{current_signal: signal}

      assert :error = TraceContext.ensure_set_from_state(state)
      assert is_nil(TraceContext.current())
    end

    test "returns error when signal has nil correlation extension" do
      signal = %Signal{
        id: "signal123",
        type: "test.event",
        source: "/test",
        extensions: %{"correlation" => nil}
      }

      state = %{current_signal: signal}

      assert :error = TraceContext.ensure_set_from_state(state)
      assert is_nil(TraceContext.current())
    end

    test "returns error when correlation extension is not a map" do
      signal = %Signal{
        id: "signal123",
        type: "test.event",
        source: "/test",
        extensions: %{"correlation" => "invalid_data"}
      }

      state = %{current_signal: signal}

      assert :error = TraceContext.ensure_set_from_state(state)
      assert is_nil(TraceContext.current())
    end

    test "returns ok when state has nil current_signal" do
      state = %{current_signal: nil}

      assert :ok = TraceContext.ensure_set_from_state(state)
      assert is_nil(TraceContext.current())
    end

    test "returns ok when state has no current_signal field" do
      state = %{other_field: "value"}

      assert :ok = TraceContext.ensure_set_from_state(state)
      assert is_nil(TraceContext.current())
    end

    test "handles partial trace data in signal extension" do
      signal = %Signal{
        id: "signal123",
        type: "test.event",
        source: "/test",
        extensions: %{
          "correlation" => %{
            trace_id: "trace123",
            span_id: "span456"
            # Missing parent_span_id and causation_id
          }
        }
      }

      state = %{current_signal: signal}

      assert :ok = TraceContext.ensure_set_from_state(state)

      expected_context = %{
        trace_id: "trace123",
        span_id: "span456"
      }

      assert ^expected_context = TraceContext.current()
    end
  end
end
