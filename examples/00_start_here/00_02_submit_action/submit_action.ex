defmodule Jido.Examples.StartHere.SubmitExpense do
  @moduledoc "Validates and prepares one submitted expense."

  alias Jido.Joi

  use Jido.Action,
    name: "start_here_submit_expense",
    schema:
      Joi.object(%{
        report_id: Joi.string() |> Joi.min(1),
        amount_cents: Joi.integer() |> Joi.min(1)
      }),
    output_schema:
      Joi.object(%{
        report_id: Joi.string(),
        amount_cents: Joi.integer(),
        status: Joi.enum([:submitted])
      })

  @impl true
  def run(input, _context), do: {:ok, Map.put(input, :status, :submitted)}
end
