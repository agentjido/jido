defmodule Jido.Examples.StartHere.HostedExpense do
  @moduledoc "Runs expense triage as a supervised AgentServer Turn."

  alias Jido.Joi

  use Jido.Agent,
    name: "start_here_hosted_expense",
    description: "Hosts one expense submission"

  state do
    schema Joi.object(%{
             report_id: Joi.string() |> Joi.default(""),
             amount_cents: Joi.integer() |> Joi.min(0) |> Joi.default(0),
             status: Joi.enum([:draft, :submitted]) |> Joi.default(:draft),
             review: Joi.enum([:none, :automatic, :manual]) |> Joi.default(:none)
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

  alias Jido.Joi

  use Jido.Flow,
    name: "start_here_hosted_expense_triage",
    schema:
      Joi.object(%{
        report_id: Joi.string() |> Joi.min(1),
        amount_cents: Joi.integer() |> Joi.min(1)
      })

  flow do
    step "triage", expense <- input() do
      review = if expense.amount_cents >= 50_000, do: :manual, else: :automatic
      {:ok, Map.merge(expense, %{status: :submitted, review: review})}
    end

    output result("triage")
  end
end
