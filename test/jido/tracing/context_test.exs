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
    assert Trace.get(traced_signal) == Map.take(trace, [:trace_id, :span_id])
    assert is_binary(trace.trace_id)
    assert is_binary(trace.span_id)
    assert trace.parent_span_id == nil
    assert trace.causation_id == nil
  end

  test "ensure_from_signal reuses an attached trace" do
    trace = Trace.new_root()
    signal = Signal.new!("test.trace.existing", %{}, source: "/test")
    assert {:ok, traced_signal} = Trace.put(signal, trace)

    attached_trace = Map.take(trace, [:trace_id, :span_id])
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
    assert Context.get() == Map.take(current, [:trace_id, :span_id])
  end

  test "propagate_to requires valid arguments and an active context" do
    signal = Signal.new!("test.trace.child", %{}, source: "/test")

    assert Context.propagate_to(signal, "cause-1") == {:error, :no_trace_context}

    assert apply(Context, :propagate_to, [:not_a_signal, "cause-1"]) ==
             {:error, :invalid_args}

    assert apply(Context, :propagate_to, [signal, :not_an_id]) == {:error, :invalid_args}
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
