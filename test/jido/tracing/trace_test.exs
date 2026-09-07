defmodule JidoTest.Tracing.TraceTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Trace, as: W3CTrace
  alias Jido.Tracing.Trace

  describe "new_root/0" do
    test "creates trace with fresh trace_id and span_id" do
      trace = Trace.new_root()

      assert is_binary(trace.trace_id)
      assert is_binary(trace.span_id)
      assert trace.parent_span_id == nil
      assert trace.causation_id == nil
    end

    test "generates unique ids each time" do
      trace1 = Trace.new_root()
      trace2 = Trace.new_root()

      refute trace1.trace_id == trace2.trace_id
      refute trace1.span_id == trace2.span_id
    end

    test "derives the W3C identifiers from the legacy UUIDs" do
      trace = Trace.new_root()
      trace_id = String.replace(trace.trace_id, "-", "")
      span_id = trace.span_id |> String.replace("-", "") |> String.slice(-16, 16)

      assert trace.traceparent == "00-#{trace_id}-#{span_id}-00"
    end
  end

  describe "child_of/2" do
    test "creates child trace inheriting trace_id" do
      parent = Trace.new_root()
      causation_id = "signal-123"

      child = Trace.child_of(parent, causation_id)

      assert child.trace_id == parent.trace_id
      assert is_binary(child.span_id)
      refute child.span_id == parent.span_id
      assert child.parent_span_id == parent.span_id
      assert child.causation_id == causation_id
    end

    test "works with just required parent fields" do
      parent = %{trace_id: "trace-abc", span_id: "span-def"}
      causation_id = "signal-456"

      child = Trace.child_of(parent, causation_id)

      assert child.trace_id == "trace-abc"
      assert child.parent_span_id == "span-def"
      assert child.causation_id == "signal-456"
      refute Map.has_key?(child, :traceparent)
      refute Map.has_key?(child, :tracestate)
    end

    test "derives the W3C child span from the legacy child span" do
      parent = Trace.new_root()

      child = Trace.child_of(parent, "signal-789")
      expected_span_id = child.span_id |> String.replace("-", "") |> String.slice(-16, 16)
      {:ok, w3c_child} = W3CTrace.from_traceparent(child.traceparent, child[:tracestate])

      assert w3c_child.trace_id == String.replace(parent.trace_id, "-", "")
      assert w3c_child.span_id == expected_span_id
      assert child.traceparent == "00-#{w3c_child.trace_id}-#{expected_span_id}-00"
    end

    test "preserves valid, different trace families and correlates their child spans" do
      legacy = %{
        trace_id: "018f6310-7d00-7000-8000-000000000001",
        span_id: "018f6310-7d00-7000-8000-000000000002"
      }

      w3c = W3CTrace.new(trace_flags: "01", tracestate: "vendor=value")

      parent =
        Map.merge(legacy, %{
          traceparent: W3CTrace.to_traceparent(w3c),
          tracestate: w3c.tracestate
        })

      child = Trace.child_of(parent, "signal-abc")
      expected_span_id = child.span_id |> String.replace("-", "") |> String.slice(-16, 16)
      {:ok, w3c_child} = W3CTrace.from_traceparent(child.traceparent, child.tracestate)

      assert child.trace_id == legacy.trace_id
      assert child.parent_span_id == legacy.span_id
      assert child.causation_id == "signal-abc"
      assert w3c_child.trace_id == w3c.trace_id
      assert w3c_child.span_id == expected_span_id
      assert w3c_child.trace_flags == "01"
      assert w3c_child.tracestate == "vendor=value"
    end
  end

  describe "put/2" do
    test "attaches trace data to a signal" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})
      trace = Trace.new_root()

      {:ok, traced_signal} = Trace.put(signal, trace)

      ext = Trace.get(traced_signal)
      assert ext[:trace_id] == trace.trace_id
      assert ext[:span_id] == trace.span_id
      assert %W3CTrace{} = W3CTrace.get(traced_signal)
      assert is_binary(Signal.get_context(traced_signal, "jidotraceid"))
      assert is_binary(Signal.get_context(traced_signal, "jidospanid"))
    end

    test "filters out nil values" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})
      trace = %{trace_id: "abc", span_id: "def", parent_span_id: nil, causation_id: nil}

      {:ok, traced_signal} = Trace.put(signal, trace)

      ext = Trace.get(traced_signal)
      assert ext[:trace_id] == "abc"
      assert ext[:span_id] == "def"
      refute Map.has_key?(ext, :parent_span_id)
      refute Map.has_key?(ext, :causation_id)
    end

    test "returns error for non-signal input" do
      assert {:error, :invalid_args} = apply(Trace, :put, ["not a signal", %{trace_id: "abc"}])
      assert {:error, :invalid_args} = apply(Trace, :put, [nil, %{trace_id: "abc"}])
    end

    test "legacy-only input removes stale W3C fields" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})
      assert {:ok, signal} = W3CTrace.put(signal, W3CTrace.new(tracestate: "vendor=old"))

      assert {:ok, signal} =
               Trace.put(signal, %{trace_id: "legacy-trace", span_id: "legacy-span"})

      assert W3CTrace.get(signal) == nil
      assert Signal.get_context(signal, "traceparent") == nil
      assert Signal.get_context(signal, "tracestate") == nil
      assert Signal.get_context(signal, "jidotraceid") == "legacy-trace"
      assert Signal.get_context(signal, "jidospanid") == "legacy-span"
    end

    test "W3C-only input removes stale legacy fields" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})

      signal =
        Enum.reduce(
          [
            {"jidotraceid", "stale-trace"},
            {"jidospanid", "stale-span"},
            {"jidoparentspanid", "stale-parent"},
            {"jidocausationid", "stale-cause"}
          ],
          signal,
          fn {name, value}, signal ->
            {:ok, signal} = Signal.put_context(signal, name, value)
            signal
          end
        )

      w3c = W3CTrace.new(trace_flags: "01", tracestate: "vendor=new")

      assert {:ok, signal} =
               Trace.put(signal, %{
                 traceparent: W3CTrace.to_traceparent(w3c),
                 tracestate: w3c.tracestate
               })

      assert W3CTrace.get(signal) == w3c
      assert Signal.get_context(signal, "jidotraceid") == nil
      assert Signal.get_context(signal, "jidospanid") == nil
      assert Signal.get_context(signal, "jidoparentspanid") == nil
      assert Signal.get_context(signal, "jidocausationid") == nil
    end
  end

  describe "get/1" do
    test "gets trace data from signal" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})
      trace = Trace.new_root()
      {:ok, traced_signal} = Trace.put(signal, trace)

      result = Trace.get(traced_signal)

      assert result[:trace_id] == trace.trace_id
      assert result[:span_id] == trace.span_id
    end

    test "returns nil for signal without trace data" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})

      assert Trace.get(signal) == nil
    end

    test "accepts a complete W3C context without legacy fields" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})
      w3c = W3CTrace.new(trace_flags: "01", tracestate: "vendor=value")
      assert {:ok, signal} = W3CTrace.put(signal, w3c)

      assert %{
               trace_id: trace_id,
               span_id: span_id,
               traceparent: traceparent,
               tracestate: "vendor=value"
             } = Trace.get(signal)

      assert trace_id == w3c.trace_id
      assert span_id == w3c.span_id
      assert traceparent == W3CTrace.to_traceparent(w3c)
    end

    test "ignores partial or malformed trace families as complete units" do
      signal = Signal.new!(%{type: "test.event", source: "/test", data: %{}})
      assert {:ok, partial_legacy} = Signal.put_context(signal, "jidotraceid", "trace-only")
      assert Trace.get(partial_legacy) == nil

      assert {:ok, malformed_w3c} =
               Signal.put_context(signal, "traceparent", "not-a-traceparent")

      assert Trace.get(malformed_w3c) == nil

      w3c = W3CTrace.new()
      assert {:ok, w3c_signal} = W3CTrace.put(partial_legacy, w3c)
      trace = Trace.get(w3c_signal)

      assert trace.trace_id == w3c.trace_id
      assert trace.span_id == w3c.span_id
      refute Map.has_key?(trace, :parent_span_id)
    end
  end
end
