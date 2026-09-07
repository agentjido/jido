defmodule JidoTest.Tracing.TraceTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
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
  end
end
