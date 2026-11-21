defmodule Jido.Examples.StartHere.ObservedExpense do
  @moduledoc "Waits for an expense decision and emits one post-commit notification."

  use Jido.Agent,
    name: "start_here_observed_expense",
    description: "Exposes one complete AgentServer lifecycle",
    plugins: [Jido.Examples.StartHere.ExpenseNotifications]

  state do
    schema Jido.Joi.object(%{
             report_id: Jido.Joi.string() |> Jido.Joi.default(""),
             amount_cents: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             status:
               Jido.Joi.enum([:draft, :approved, :rejected, :expired])
               |> Jido.Joi.default(:draft)
           })
  end

  routes do
    signal_source "/examples/start_here/observed_expense"

    route "examples.start_here.observed.review",
          Jido.Examples.StartHere.ObservedExpense.Approval,
          as: :review
  end

  @doc "Builds one decision Signal for the open approval wait."
  def decision_signal(report_id, decision) when decision in [:approve, :reject] do
    Jido.Signal.new(
      "examples.start_here.observed.#{decision}",
      %{report_id: report_id},
      source: "/examples/start_here/reviewer"
    )
  end
end

defmodule Jido.Examples.StartHere.ObservedExpense.Approval do
  @moduledoc false

  alias Jido.Examples.StartHere.ExpenseNotification

  use Jido.Flow,
    name: "start_here_observed_expense_approval",
    schema:
      Jido.Joi.object(%{
        report_id: Jido.Joi.string() |> Jido.Joi.min(1),
        amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)
      })

  flow do
    step "request", request <- input() do
      {:ok, request}
    end

    selection "decision" do
      needs ["request"]

      await "approved",
        event: "examples.start_here.observed.approve",
        match: %{report_id: result("request", :report_id)}

      await "rejected",
        event: "examples.start_here.observed.reject",
        match: %{report_id: result("request", :report_id)}

      timer "expired", after_ms: 60_000
    end

    step "finish", values <- %{request: result("request"), decision: result("decision")} do
      status =
        case values.decision.selected do
          "approved" -> :approved
          "rejected" -> :rejected
          "expired" -> :expired
        end

      state = %{
        report_id: values.request.report_id,
        amount_cents: values.request.amount_cents,
        status: status
      }

      {:ok, state, [%ExpenseNotification{report_id: values.request.report_id, status: status}]}
    end

    output result("finish")
  end
end
