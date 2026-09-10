defmodule JidoTest.Tracing.TraceTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Trace, as: SignalTrace
  alias Jido.Tracing.Trace

  test "new roots use one valid W3C representation" do
    trace = Trace.new_root()

    assert {:ok, parsed} = SignalTrace.from_traceparent(trace.traceparent)
    assert parsed.trace_id == trace.trace_id
    assert parsed.span_id == trace.span_id
    assert trace.trace_flags == "00"
    refute Map.has_key?(trace, :parent_span_id)
  end

  test "children retain W3C sampling data and explicit causal data" do
    parent = SignalTrace.new(trace_flags: "01", tracestate: "vendor=value")

    parent = %{
      trace_id: parent.trace_id,
      span_id: parent.span_id,
      trace_flags: parent.trace_flags,
      traceparent: SignalTrace.to_traceparent(parent),
      tracestate: parent.tracestate
    }

    child = Trace.child_of(parent, "signal-1")

    assert child.trace_id == parent.trace_id
    assert child.span_id != parent.span_id
    assert child.parent_span_id == parent.span_id
    assert child.causation_id == "signal-1"
    assert child.trace_flags == "01"
    assert child.tracestate == "vendor=value"
  end

  test "put and get use Signal.Trace and remove old private trace fields" do
    signal = Signal.new!("test.trace", %{}, source: "/test")

    signal =
      Enum.reduce(~w(jidotraceid jidospanid jidoparentspanid), signal, fn name, signal ->
        {:ok, signal} = Signal.put_context(signal, name, "old")
        signal
      end)

    trace = Trace.new_root() |> Map.put(:causation_id, "cause-1")
    assert {:ok, signal} = Trace.put(signal, trace)
    assert Trace.get(signal) == trace
    assert %SignalTrace{} = SignalTrace.get(signal)
    assert Signal.get_context(signal, "jidocausationid") == "cause-1"

    for name <- ~w(jidotraceid jidospanid jidoparentspanid) do
      assert Signal.get_context(signal, name) == nil
    end
  end

  test "invalid and legacy-only values are rejected" do
    signal = Signal.new!("test.trace", %{}, source: "/test")

    assert Trace.child_of(%{trace_id: "old", span_id: "old"}, "cause") ==
             {:error, :invalid_trace_context}

    assert Trace.put(signal, %{trace_id: "old", span_id: "old"}) ==
             {:error, :invalid_trace_context}

    assert Trace.get(signal) == nil
  end
end
