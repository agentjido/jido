defmodule Jido.Examples.Signals.SignalEnvelope.OrderSubmitted do
  use Jido.Signal,
    type: "examples.orders.submitted",
    default_source: "/examples/orders",
    datacontenttype: "application/json",
    schema:
      Jido.Joi.object(%{
        "order_id" => Jido.Joi.string() |> Jido.Joi.min(1),
        "total_cents" => Jido.Joi.integer() |> Jido.Joi.min(0)
      })
end
