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

defmodule Jido.Examples.BoundedIteration.Pipeline do
  @moduledoc "A while loop validates each replacement state and permits at most three repairs."

  @state_schema Zoi.object(%{
                  missing: Zoi.integer() |> Zoi.min(0),
                  repairs: Zoi.integer() |> Zoi.min(0)
                })

  use Jido.Flow,
    name: "workflow_iteration",
    schema:
      Zoi.object(%{
        missing: Zoi.integer() |> Zoi.min(0),
        repair_size: Zoi.integer() |> Zoi.min(1) |> Zoi.default(1)
      }),
    output_schema:
      Zoi.object(%{
        result:
          Zoi.object(%{
            iterations: Zoi.integer() |> Zoi.min(0),
            state: @state_schema
          })
      })

  flow do
    iterate "repair" do
      state @state_schema, initial: %{missing: input(:missing), repairs: 0}

      action [current <- state(), repair_size <- input(:repair_size)] do
        next = %{
          current
          | missing: current.missing - repair_size,
            repairs: current.repairs + 1
        }

        {:ok, next}
      end

      update body_result()
      while state(:missing) > 0
      max_iterations 3
    end

    output %{result: result("repair")}
  end
end
