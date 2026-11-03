defmodule JidoTest.Telemetry.ContextTest do
  use Covenant.Case, component: "jido.telemetry", async: true

  @moduletag obligation: ["jido.telemetry.I5", "jido.telemetry.I6"]

  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Trace
  alias Jido.Trace.Context

  setup do
    Context.clear()
    on_exit(&Context.clear/0)
  end

  test "an untraced Signal starts one local root context" do
    signal = Signal.new!("test.trace.root", %{}, source: "/test")
    trace = Context.begin_turn(signal)

    assert Context.get() == trace
    assert is_binary(Trace.to_traceparent(trace))
    assert trace.parent_span_id == nil
    assert SignalContext.get_trace(signal) == nil
  end

  test "an incoming carrier becomes the parent of the local Turn" do
    parent = Trace.new()
    signal = Signal.new!("test.trace.incoming", %{}, source: "/test")
    assert {:ok, signal} = SignalContext.put_trace(signal, parent)

    child = Context.begin_turn(signal)

    assert child.trace_id == parent.trace_id
    assert child.span_id != parent.span_id
    assert child.parent_span_id == parent.span_id
    assert child.causation_id == nil
    assert Context.get() == child
  end

  test "old or malformed context does not become a parent" do
    signal = Signal.new!("test.trace.invalid", %{}, source: "/test")
    assert {:ok, signal} = Signal.put_context(signal, "jidotraceid", "old")
    assert {:ok, signal} = Signal.put_context(signal, "traceparent", "malformed")

    trace = Context.begin_turn(signal)

    refute Trace.to_traceparent(trace) == "malformed"
    assert trace.parent_span_id == nil
  end

  test "propagation carries the active Turn span and cause" do
    active = Trace.new()
    Context.put(active)
    target = Signal.new!("test.trace.target", %{}, source: "/test")

    assert {:ok, target} = Context.propagate_to(target, "source-1")
    propagated = SignalContext.get_trace(target)

    assert propagated.trace_id == active.trace_id
    assert propagated.span_id == active.span_id
    assert propagated.causation_id == "source-1"
  end

  test "propagation validates its boundary" do
    signal = Signal.new!("test.trace.target", %{}, source: "/test")

    assert Context.propagate_to(signal, "source-1") == {:error, :no_trace_context}
    assert Context.propagate_to(signal, :bad) == {:error, :invalid_args}
    assert_raise FunctionClauseError, fn -> apply(Context, :put, [%{trace_id: "bad"}]) end
  end

  test "captured task context is restored after success and failure" do
    parent = Trace.new()
    Context.put(parent)
    captured = Context.capture()
    Context.clear()

    assert Context.with_context(captured, fn -> Context.get() end) == parent
    assert Context.get() == nil
    assert catch_throw(Context.with_context(parent, fn -> throw(:failed) end)) == :failed
    assert Context.get() == nil
  end

  test "clear removes the current context" do
    assert :ok = Context.put(Trace.new())
    assert :ok = Context.put(nil)
    assert Context.get() == nil
    assert :ok = Context.put(Trace.new())
    assert :ok = Context.clear()
    assert Context.get() == nil
  end

  test "context input functions reject unsupported values" do
    assert_raise FunctionClauseError, fn -> apply(Context, :put, [:invalid]) end

    assert_raise FunctionClauseError, fn ->
      apply(Context, :with_context, [:invalid, fn -> :ok end])
    end

    assert_raise FunctionClauseError, fn ->
      apply(Context, :with_context, [nil, :not_a_function])
    end

    assert_raise FunctionClauseError, fn ->
      apply(Context, :with_context, [Context.capture(), :not_a_function])
    end
  end
end
