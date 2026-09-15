defmodule Jido.Dispatch.PreparationTest do
  use ExUnit.Case, async: true

  alias Jido.Dispatch.Preparation
  alias Jido.Signal
  alias Jido.Tracing.{Context, Trace}

  test "trace propagation keeps exact Signals when context is absent or invalid" do
    source = Signal.new!("source", %{}, source: "/test")
    signal = Signal.new!("output", %{}, source: "/test")

    for context <- [nil, %{trace_id: "invalid"}] do
      Context.put(context)
      assert Preparation.propagate(signal, source) === signal
    end
  end

  test "trace propagation preserves identity and adds the current cause" do
    source = Signal.new!("source", %{}, source: "/test")
    signal = Signal.new!("output", %{value: 1}, source: "/test")
    trace = Context.begin_turn(source)
    propagated = Preparation.propagate(signal, source)

    assert propagated.id == signal.id
    assert propagated.data == signal.data
    assert Trace.get(propagated).trace_id == trace.trace_id
    assert Trace.get(propagated).causation_id == source.id
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

    assert Preparation.inherit_bus_scope(targets, nil) == targets

    assert Preparation.inherit_bus_scope({:pid, target: self()}, :inherited) ==
             {:pid, target: self()}
  end
end
