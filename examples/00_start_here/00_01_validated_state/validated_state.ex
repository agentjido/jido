defmodule Jido.Examples.StartHere.ValidatedExpense do
  @moduledoc "A portable expense record with validated state and defaults."

  alias Jido.Joi

  use Jido.Agent,
    name: "start_here_validated_expense",
    description: "Keeps one expense request"

  state do
    schema Joi.object(%{
             report_id: Joi.string() |> Joi.default(""),
             amount_cents: Joi.integer() |> Joi.min(0) |> Joi.default(0),
             status:
               Joi.enum([:draft, :submitted, :approved, :rejected])
               |> Joi.default(:draft)
           })
  end
end
