defmodule JidoTest.Examples.SharedBudgetWorker do
  @moduledoc false
  use Jido.Agent, name: "test_shared_budget_worker"

  agent do
    schema Zoi.object(%{
             job: Zoi.string() |> Zoi.default(""),
             value: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/test/examples/shared_budget"

    route "examples.research.shared_budget.work" do
      action %{job: job, value: value},
        schema: Zoi.object(%{job: Zoi.string(), value: Zoi.integer()}),
        context: context do
        send(context.observer, {:budget_work, job, self()})

        receive do
          :finish -> {:ok, %{job: job, value: value * 2}}
          :fail -> {:error, Jido.Action.Error.execution_error("controlled review failure")}
        end
      end

      define :work, args: [:job, :value]
    end
  end
end
