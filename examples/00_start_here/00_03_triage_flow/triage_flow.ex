defmodule Jido.Examples.StartHere.TriageExpense.Submit do
  @moduledoc false

  use Jido.Action,
    name: "start_here_triage_submit",
    schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string() |> Jido.Joi.min(1),
        amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)
      })

  @impl true
  def run(input, _context), do: {:ok, Map.put(input, :status, :submitted)}
end

defmodule Jido.Examples.StartHere.TriageExpense do
  @moduledoc "Submits and classifies one expense with a deterministic Flow."

  use Jido.Flow,
    name: "start_here_triage_expense",
    schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string() |> Jido.Joi.min(1),
        amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)
      }),
    output_schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string(),
        amount_cents: Jido.Joi.integer(),
        status: Jido.Joi.enum([:submitted]),
        review: Jido.Joi.enum([:automatic, :manual])
      })

  flow do
    step "submit",
      action: Jido.Examples.StartHere.TriageExpense.Submit,
      params: %{report_id: input(:report_id), amount_cents: input(:amount_cents)}

    step "classify", expense <- result("submit") do
      review = if expense.amount_cents >= 50_000, do: :manual, else: :automatic
      {:ok, Map.put(expense, :review, review)}
    end

    output result("classify")
  end
end
