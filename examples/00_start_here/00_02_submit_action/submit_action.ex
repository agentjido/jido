defmodule Jido.Examples.StartHere.SubmitExpense do
  @moduledoc "Validates and prepares one submitted expense."

  use Jido.Action,
    name: "start_here_submit_expense",
    schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string() |> Jido.Joi.min(1),
        amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)
      }),
    output_schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string(),
        amount_cents: Jido.Joi.integer(),
        status: Jido.Joi.enum([:submitted])
      })

  @impl true
  def run(input, _context), do: {:ok, Map.put(input, :status, :submitted)}
end
