defmodule Jido.Tracing.ContextTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Tracing.{Context, Trace}

  setup do
    Context.clear()
    on_exit(&Context.clear/0)
  end

  test "an untraced Signal starts one local root context" do
    signal = Signal.new!("test.trace.root", %{}, source: "/test")
    trace = Context.begin_turn(signal)

    assert Context.get() == trace
    assert is_binary(trace.traceparent)
    refute Map.has_key?(trace, :parent_span_id)
    assert Trace.get(signal) == nil
  end

  test "an incoming carrier becomes the parent of the local Turn" do
    parent = Trace.new_root()
    signal = Signal.new!("test.trace.incoming", %{}, source: "/test")
    assert {:ok, signal} = Trace.put(signal, parent)

    child = Context.begin_turn(signal)

    assert child.trace_id == parent.trace_id
    assert child.span_id != parent.span_id
    assert child.parent_span_id == parent.span_id
    refute Map.has_key?(child, :causation_id)
    assert Context.get() == child
  end

  test "old or malformed context does not become a parent" do
    signal = Signal.new!("test.trace.invalid", %{}, source: "/test")
    assert {:ok, signal} = Signal.put_context(signal, "jidotraceid", "old")
    assert {:ok, signal} = Signal.put_context(signal, "traceparent", "malformed")

    trace = Context.begin_turn(signal)

    refute trace.traceparent == "malformed"
    refute Map.has_key?(trace, :parent_span_id)
  end

  test "propagation carries the active Turn span and cause" do
    active = Trace.new_root()
    Context.put(active)
    target = Signal.new!("test.trace.target", %{}, source: "/test")

    assert {:ok, target} = Context.propagate_to(target, "source-1")
    propagated = Trace.get(target)

    assert propagated.trace_id == active.trace_id
    assert propagated.span_id == active.span_id
    assert propagated.causation_id == "source-1"
  end

  test "propagation validates its boundary" do
    signal = Signal.new!("test.trace.target", %{}, source: "/test")

    assert Context.propagate_to(signal, "source-1") == {:error, :no_trace_context}
    assert Context.propagate_to(signal, :bad) == {:error, :invalid_args}
    Context.put(%{trace_id: "bad"})
    assert Context.propagate_to(signal, "source-1") == {:error, :invalid_trace_context}
  end

  test "captured task context is restored after success and failure" do
    parent = Trace.new_root()
    Context.put(parent)
    captured = Context.capture()
    Context.clear()

    assert Context.with_context(captured, fn -> Context.get() end) == parent
    assert Context.get() == nil
    assert catch_throw(Context.with_context(parent, fn -> throw(:failed) end)) == :failed
    assert Context.get() == nil
  end

  test "clear removes the current context" do
    Context.put(Trace.new_root())
    assert :ok = Context.clear()
    assert Context.get() == nil
  end
end
