defmodule Jido.Examples.StartHere.HostedExpense do
  @moduledoc "Runs expense triage as a supervised AgentServer Turn."

  use Jido.Agent,
    name: "start_here_hosted_expense",
    description: "Hosts one expense submission"

  state do
    schema Jido.Joi.object(%{
             report_id: Jido.Joi.string() |> Jido.Joi.default(""),
             amount_cents: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             status: Jido.Joi.enum([:draft, :submitted]) |> Jido.Joi.default(:draft),
             review: Jido.Joi.enum([:none, :automatic, :manual]) |> Jido.Joi.default(:none)
           })
  end

  routes do
    signal_source "/examples/start_here/hosted_expense"

    route "examples.start_here.hosted.submit",
          Jido.Examples.StartHere.HostedExpense.Triage,
          as: :submit
  end
end

defmodule Jido.Examples.StartHere.HostedExpense.Triage do
  @moduledoc false

  use Jido.Flow,
    name: "start_here_hosted_expense_triage",
    schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string() |> Jido.Joi.min(1),
        amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)
      })

  flow do
    step "triage", expense <- input() do
      review = if expense.amount_cents >= 50_000, do: :manual, else: :automatic
      {:ok, Map.merge(expense, %{status: :submitted, review: review})}
    end

    output result("triage")
  end
end
