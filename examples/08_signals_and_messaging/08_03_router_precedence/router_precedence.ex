defmodule Jido.Examples.Signals.RouterPrecedence.OrderRouter do
  use Jido.Signal.Router

  route "examples.orders.created", :exact
  route "examples.orders.*", :order_event
  route "examples.**", :example_event
  route "**", :all_events
end
