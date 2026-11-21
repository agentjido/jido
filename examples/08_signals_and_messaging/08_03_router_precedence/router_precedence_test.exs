Code.require_file("router_precedence.ex", __DIR__)

defmodule Jido.Examples.Signals.RouterPrecedenceTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Signals.RouterPrecedence.OrderRouter

  test "returns matching targets in precedence order" do
    signal = Jido.Signal.new!("examples.orders.created", %{order_id: "order-1"}, source: "/orders")

    assert {:ok, [:exact, :order_event, :example_event, :all_events]} = OrderRouter.route(signal)
  end

  test "does not run a target during routing" do
    signal = Jido.Signal.new!("examples.users.created", %{}, source: "/users")
    assert {:ok, [:example_event, :all_events]} = OrderRouter.route(signal)
  end
end
