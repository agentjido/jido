defmodule Jido.Signal.Dispatch.ScopeTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Dispatch

  test "Bus scope inheritance preserves explicit scope, target order and nested lists" do
    targets = [
      {:pid, target: self()},
      [{:bus, target: :first}, {:bus, target: :second, jido: :explicit}],
      {:bus, target: :third, jido: nil}
    ]

    assert Dispatch.inherit_bus_scope(targets, :inherited) == [
             {:pid, target: self()},
             [{:bus, jido: :inherited, target: :first}, {:bus, target: :second, jido: :explicit}],
             {:bus, target: :third, jido: nil}
           ]

    for scope <- [nil, "invalid", 0] do
      assert Dispatch.inherit_bus_scope(targets, scope) == targets
    end

    assert Dispatch.inherit_bus_scope({:pid, target: self()}, :inherited) ==
             {:pid, target: self()}
  end
end
