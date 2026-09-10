defmodule Jido.Examples.SharedBudget.Worker do
  @moduledoc "A finite default worker for the shared-budget service."
  use Jido.Agent, name: "research_budget_worker"

  agent do
    schema Zoi.object(%{
             job: Zoi.string() |> Zoi.default(""),
             value: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/research/shared_budget"

    route "examples.research.shared_budget.work" do
      action %{job: job, value: value},
        schema: Zoi.object(%{job: Zoi.string(), value: Zoi.integer()}),
        context: _context do
        {:ok, %{job: job, value: value * 2}}
      end

      define :work, args: [:job, :value]
    end
  end
end
