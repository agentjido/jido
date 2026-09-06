defmodule Jido.Examples.BoundedIteration.Pipeline do
  @moduledoc "A while loop validates each replacement state and permits at most three repairs."
  use Jido.Flow, name: "workflow_iteration"

  flow do
    iterate "repair" do
      state Zoi.object(%{
              missing: Zoi.integer() |> Zoi.min(0),
              repairs: Zoi.integer() |> Zoi.min(0)
            }),
            initial: %{missing: input(:missing), repairs: 0}

      action [current <- state(), index <- iteration_index()], context: context do
        Jido.Examples.Workflow.Observation.record(context, {:iteration, index}, current)
        next = %{current | missing: current.missing - 1, repairs: current.repairs + 1}
        next = if context[:invalid_update], do: %{next | missing: "invalid"}, else: next
        {:ok, next}
      end

      update body_result()
      while state(:missing) > 0
      max_iterations 3
    end

    output %{result: result("repair")}
  end
end

defmodule Jido.Examples.BoundedIteration do
  @moduledoc "Local repair state is separate from the Agent's committed state."
  use Jido.Agent, name: "workflow_iteration_agent"

  agent do
    schema Zoi.object(%{result: Zoi.map() |> Zoi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.iteration", Jido.Examples.BoundedIteration.Pipeline do
      define :repair
    end
  end
end
