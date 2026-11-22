defmodule Jido.Examples.Signals.SignalEnvelope.OrderSubmitted do
  alias Jido.Joi

  use Jido.Signal,
    type: "examples.orders.submitted",
    default_source: "/examples/orders",
    datacontenttype: "application/json",
    schema:
      Joi.object(%{
        "order_id" => Joi.string() |> Joi.min(1),
        "total_cents" => Joi.integer() |> Joi.min(0)
      })
end
