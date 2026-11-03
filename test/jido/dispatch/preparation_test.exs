defmodule Jido.Dispatch.PreparationTest do
  use ExUnit.Case, async: true

  alias Jido.Dispatch.Preparation
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Trace
  alias Jido.Trace.Context

  test "trace propagation keeps exact Signals when context is absent or invalid" do
    source = Signal.new!("source", %{}, source: "/test")
    signal = Signal.new!("output", %{}, source: "/test")
    {:ok, traced} = SignalContext.put_trace(signal, Trace.new())

    for context <- [nil], signal <- [signal, traced] do
      Context.put(context)
      assert Preparation.propagate(signal, source) === signal
    end
  end

  test "an invalid cause keeps the original outgoing trace" do
    source = Signal.new!("source", %{}, source: "/test")
    signal = Signal.new!("output", %{}, source: "/test")
    {:ok, signal} = SignalContext.put_trace(signal, Trace.new())
    Context.begin_turn(source)

    assert Preparation.propagate(signal, %{source | id: nil}) === signal
  end

  test "trace propagation preserves identity and adds the current cause" do
    source = Signal.new!("source", %{}, source: "/test")
    signal = Signal.new!("output", %{value: 1}, source: "/test", subject: "worker")
    {:ok, signal} = Signal.put_context(signal, "tenant", "blue")
    {:ok, signal} = SignalContext.put_trace(signal, Trace.new())
    trace = Context.begin_turn(source)
    propagated = Preparation.propagate(signal, source)

    assert Map.drop(propagated, [:extensions]) == Map.drop(signal, [:extensions])
    assert Signal.get_context(propagated, "tenant") == "blue"
    assert SignalContext.get_trace(propagated).trace_id == trace.trace_id
    assert SignalContext.get_trace(propagated).span_id == trace.span_id
    assert SignalContext.get_trace(propagated).causation_id == source.id
    assert Context.get() == trace
  end

  test "Bus scope inheritance preserves explicit scope, target order and nested lists" do
    targets = [
      {:pid, target: self()},
      [{:bus, target: :first}, {:bus, target: :second, jido: :explicit}],
      {:bus, target: :third, jido: nil}
    ]

    assert Preparation.inherit_bus_scope(targets, :inherited) == [
             {:pid, target: self()},
             [{:bus, jido: :inherited, target: :first}, {:bus, target: :second, jido: :explicit}],
             {:bus, target: :third, jido: nil}
           ]

    for scope <- [nil, "invalid", 0] do
      assert Preparation.inherit_bus_scope(targets, scope) == targets
    end

    assert Preparation.inherit_bus_scope({:pid, target: self()}, :inherited) ==
             {:pid, target: self()}
  end
end
