defmodule JidoTest.TraceRuntimeTest do
  use Covenant.Case, component: "jido.telemetry", async: true

  @moduletag obligation: "jido.telemetry.I5"

  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Trace

  test "new roots use one valid W3C representation" do
    trace = Trace.new()

    assert {:ok, parsed} = trace |> Trace.to_traceparent() |> Trace.from_traceparent()
    assert parsed.trace_id == trace.trace_id
    assert parsed.span_id == trace.span_id
    assert trace.trace_flags == "00"
    assert trace.parent_span_id == nil
  end

  test "children retain W3C sampling data and explicit causal data" do
    parent = Trace.new(trace_flags: "01", tracestate: "vendor=value")
    child = Trace.child(parent, causation_id: "signal-1")

    assert child.trace_id == parent.trace_id
    assert child.span_id != parent.span_id
    assert child.parent_span_id == parent.span_id
    assert child.causation_id == "signal-1"
    assert child.trace_flags == "01"
    assert child.tracestate == "vendor=value"
  end

  test "children require the canonical Trace value" do
    assert_raise FunctionClauseError, fn -> apply(Trace, :child, [%{trace_id: "old"}]) end
  end

  test "Signal context uses the canonical Trace and removes old private fields" do
    signal = Signal.new!("test.trace", %{}, source: "/test")

    signal =
      Enum.reduce(~w(jidotraceid jidospanid jidoparentspanid), signal, fn name, signal ->
        {:ok, signal} = Signal.put_context(signal, name, "old")
        signal
      end)

    trace = Trace.new() |> Trace.with_causation("cause-1")
    assert {:ok, signal} = SignalContext.put_trace(signal, trace)
    assert SignalContext.get_trace(signal) == trace
    assert %Trace{} = SignalContext.get_trace(signal)
    assert Signal.get_context(signal, "jidocausationid") == "cause-1"

    for name <- ~w(jidotraceid jidospanid jidoparentspanid) do
      assert Signal.get_context(signal, name) == nil
    end
  end

  test "invalid and legacy-only values are rejected" do
    signal = Signal.new!("test.trace", %{}, source: "/test")

    assert SignalContext.put_trace(signal, %{trace_id: "old"}) == {:error, :invalid_args}
    assert SignalContext.get_trace(signal) == nil
    assert_raise FunctionClauseError, fn -> apply(Trace, :child, [nil]) end
    assert_raise ArgumentError, fn -> Trace.child(Trace.new(), causation_id: 1) end
    assert SignalContext.put_trace(signal, nil) == {:error, :invalid_args}
    assert SignalContext.put_trace(nil, Trace.new()) == {:error, :invalid_args}
  end

  test "telemetry context contains only validated trace and causation identifiers" do
    trace = Trace.child(Trace.new(), causation_id: "cause")

    assert Trace.telemetry_context(trace) ==
             Map.take(trace, [:trace_id, :span_id, :parent_span_id, :causation_id])

    assert_raise FunctionClauseError, fn -> apply(Trace, :telemetry_context, [%{}]) end
    assert SignalContext.trace_names() == ["traceparent", "tracestate", "jidocausationid"]
  end
end
