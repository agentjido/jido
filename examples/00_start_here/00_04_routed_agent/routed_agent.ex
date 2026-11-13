defmodule Jido.Examples.StartHere.RoutedExpense do
  @moduledoc "Routes one expense Signal to a pure triage Flow."

  use Jido.Agent,
    name: "start_here_routed_expense",
    description: "Routes one expense submission"

  state do
    schema Jido.Joi.object(%{
             report_id: Jido.Joi.string() |> Jido.Joi.default(""),
             amount_cents: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             status: Jido.Joi.enum([:draft, :submitted]) |> Jido.Joi.default(:draft),
             review: Jido.Joi.enum([:none, :automatic, :manual]) |> Jido.Joi.default(:none)
           })
  end

  routes do
    signal_source "/examples/start_here/routed_expense"

    route "examples.start_here.expense.submit",
          Jido.Examples.StartHere.RoutedExpense.Triage,
          as: :submit
  end
end

defmodule Jido.Examples.StartHere.RoutedExpense.Triage do
  @moduledoc false

  use Jido.Flow,
    name: "start_here_routed_expense_triage",
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
    step "triage", expense <- input() do
      review = if expense.amount_cents >= 50_000, do: :manual, else: :automatic
      {:ok, Map.merge(expense, %{status: :submitted, review: review})}
    end

    output result("triage")
  end
end
