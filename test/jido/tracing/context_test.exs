defmodule Jido.Tracing.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Tracing.{Context, Trace}

  setup do
    Context.clear()
    on_exit(&Context.clear/0)
  end

  test "ensure_from_signal creates, stores, and attaches a root trace" do
    signal = Signal.new!("test.trace.root", %{}, source: "/test")

    {traced_signal, trace} = Context.ensure_from_signal(signal)

    assert Context.get() == trace
    attached = Trace.get(traced_signal)
    assert Map.take(trace, Map.keys(attached)) == attached
    assert is_binary(trace.trace_id)
    assert is_binary(trace.span_id)
    assert trace.parent_span_id == nil
    assert trace.causation_id == nil
  end

  test "ensure_from_signal reuses an attached trace" do
    trace = Trace.new_root()
    signal = Signal.new!("test.trace.existing", %{}, source: "/test")
    assert {:ok, traced_signal} = Trace.put(signal, trace)

    attached_trace = Trace.get(traced_signal)
    assert Context.ensure_from_signal(traced_signal) == {traced_signal, attached_trace}
    assert Context.get() == attached_trace
  end

  test "set_from_signal preserves the context when the signal has no trace" do
    current = Trace.new_root()
    current_signal = Signal.new!("test.trace.current", %{}, source: "/test")
    assert {:ok, current_signal} = Trace.put(current_signal, current)
    assert :ok = Context.set_from_signal(current_signal)

    empty_signal = Signal.new!("test.trace.empty", %{}, source: "/test")
    assert Context.set_from_signal(empty_signal) == {:error, :no_trace}
    assert Context.get() == Trace.get(current_signal)
  end

  test "propagate_to requires valid arguments and an active context" do
    signal = Signal.new!("test.trace.child", %{}, source: "/test")

    assert Context.propagate_to(signal, "cause-1") == {:error, :no_trace_context}

    assert apply(Context, :propagate_to, [:not_a_signal, "cause-1"]) ==
             {:error, :invalid_args}

    assert apply(Context, :propagate_to, [signal, :not_an_id]) == {:error, :invalid_args}
  end

  test "propagate_to rejects a malformed process context without exiting" do
    signal = Signal.new!("test.trace.child", %{}, source: "/test")
    Process.put({:jido, :trace_context}, %{trace_id: "partial"})

    assert Context.propagate_to(signal, "cause-1") == {:error, :invalid_trace_context}
  end

  test "ensure_from_signal replaces partial legacy and malformed W3C context" do
    signal = Signal.new!("test.trace.invalid", %{}, source: "/test")
    assert {:ok, signal} = Signal.put_context(signal, "jidotraceid", "partial")
    assert {:ok, signal} = Signal.put_context(signal, "traceparent", "malformed")

    {traced, trace} = Context.ensure_from_signal(signal)

    attached = Trace.get(traced)
    assert Map.take(trace, Map.keys(attached)) == attached
    assert Signal.get_context(traced, "traceparent") == trace.traceparent
    assert Signal.get_context(traced, "jidotraceid") == trace.trace_id
    assert Signal.get_context(traced, "jidospanid") == trace.span_id
    refute Signal.get_context(traced, "traceparent") == "malformed"

    {:ok, w3c} = Jido.Signal.Trace.from_traceparent(trace.traceparent)
    assert w3c.trace_id == String.replace(trace.trace_id, "-", "")
    assert w3c.span_id == trace.span_id |> String.replace("-", "") |> String.slice(-16, 16)
  end

  test "propagate_to attaches a child span" do
    source = Signal.new!("test.trace.source", %{}, source: "/test")
    {_source, parent} = Context.ensure_from_signal(source)
    target = Signal.new!("test.trace.target", %{}, source: "/test")

    assert {:ok, traced_target} = Context.propagate_to(target, source.id)
    child = Trace.get(traced_target)

    assert child.trace_id == parent.trace_id
    assert child.span_id != parent.span_id
    assert child.parent_span_id == parent.span_id
    assert child.causation_id == source.id
    assert Context.get() == parent
  end

  test "propagate_to preserves W3C flags and tracestate with legacy fields" do
    source = Signal.new!("test.trace.w3c", %{}, source: "/test")
    w3c = Jido.Signal.Trace.new(trace_flags: "01", tracestate: "vendor=value")
    assert {:ok, source} = Jido.Signal.Trace.put(source, w3c)
    assert :ok = Context.set_from_signal(source)

    target = Signal.new!("test.trace.child", %{}, source: "/test")
    assert {:ok, target} = Context.propagate_to(target, source.id)

    child = Jido.Signal.Trace.get(target)
    assert child.trace_id == w3c.trace_id
    assert child.span_id != w3c.span_id
    assert child.trace_flags == "01"
    assert child.tracestate == "vendor=value"
    assert Signal.get_context(target, "jidotraceid") == child.trace_id

    legacy_span_id = Signal.get_context(target, "jidospanid")

    expected_w3c_span_id =
      legacy_span_id |> String.replace("-", "") |> String.slice(-16, 16)

    assert child.span_id == expected_w3c_span_id
    assert Signal.get_context(target, "jidoparentspanid") == w3c.span_id
    assert Signal.get_context(target, "jidocausationid") == source.id
  end

  test "clear removes the current context" do
    signal = Signal.new!("test.trace.clear", %{}, source: "/test")
    Context.ensure_from_signal(signal)
    refute Context.get() == nil

    assert Context.clear() == :ok
    assert Context.get() == nil
  end

  test "telemetry metadata prefixes keys and omits missing values" do
    trace = %{
      trace_id: "trace-1",
      span_id: "span-1",
      parent_span_id: "parent-1",
      causation_id: nil
    }

    signal = Signal.new!("test.trace.telemetry", %{}, source: "/test")
    assert {:ok, signal} = Trace.put(signal, trace)
    assert :ok = Context.set_from_signal(signal)

    assert Context.to_telemetry_metadata() == %{
             jido_trace_id: "trace-1",
             jido_span_id: "span-1",
             jido_parent_span_id: "parent-1"
           }

    Context.clear()
    assert Context.to_telemetry_metadata() == %{}
  end
end
