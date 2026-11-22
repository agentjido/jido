defmodule Jido.Examples.StartHere.TriageExpense.Submit do
  @moduledoc false

  alias Jido.Joi

  use Jido.Action,
    name: "start_here_triage_submit",
    schema:
      Joi.object(%{
        report_id: Joi.string() |> Joi.min(1),
        amount_cents: Joi.integer() |> Joi.min(1)
      })

  @impl true
  def run(input, _context), do: {:ok, Map.put(input, :status, :submitted)}
end

defmodule Jido.Examples.StartHere.TriageExpense do
  @moduledoc "Submits and classifies one expense with a deterministic Flow."

  alias Jido.Joi

  use Jido.Flow,
    name: "start_here_triage_expense",
    schema:
      Joi.object(%{
        report_id: Joi.string() |> Joi.min(1),
        amount_cents: Joi.integer() |> Joi.min(1)
      }),
    output_schema:
      Joi.object(%{
        report_id: Joi.string(),
        amount_cents: Joi.integer(),
        status: Joi.enum([:submitted]),
        review: Joi.enum([:automatic, :manual])
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
