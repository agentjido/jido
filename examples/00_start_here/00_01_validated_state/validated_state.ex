defmodule Jido.Examples.StartHere.ValidatedExpense do
  @moduledoc "A portable expense record with validated state and defaults."

  use Jido.Agent,
    name: "start_here_validated_expense",
    description: "Keeps one expense request"

  state do
    schema Jido.Joi.object(%{
             report_id: Jido.Joi.string() |> Jido.Joi.default(""),
             amount_cents: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             status:
               Jido.Joi.enum([:draft, :submitted, :approved, :rejected])
               |> Jido.Joi.default(:draft)
           })
  end
end
