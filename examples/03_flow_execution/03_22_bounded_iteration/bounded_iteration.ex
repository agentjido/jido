defmodule Jido.Examples.BoundedIteration do
  @moduledoc "Local repair state is separate from the Agent's committed state."
  use Jido.Agent, name: "workflow_iteration_agent"

  state do
    schema Jido.Joi.object(%{result: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.iteration", Jido.Examples.BoundedIteration.Pipeline, as: :repair
  end
end

defmodule Jido.Examples.BoundedIteration.Repair do
  @moduledoc false
  use Jido.Action,
    name: "workflow_iteration_repair"

  def run(%{current: current, repair_size: repair_size}, _context) do
    {:ok, %{current | missing: current.missing - repair_size, repairs: current.repairs + 1}}
  end
end

defmodule Jido.Examples.BoundedIteration.Pipeline do
  @moduledoc "A while loop validates each replacement state and permits at most three repairs."

  @state_schema Jido.Joi.object(%{
                  missing: Jido.Joi.integer() |> Jido.Joi.min(0),
                  repairs: Jido.Joi.integer() |> Jido.Joi.min(0)
                })

  use Jido.Flow,
    name: "workflow_iteration",
    schema:
      Jido.Joi.object(%{
        missing: Jido.Joi.integer() |> Jido.Joi.min(0),
        repair_size: Jido.Joi.integer() |> Jido.Joi.min(1) |> Jido.Joi.default(1)
      }),
    output_schema:
      Jido.Joi.object(%{
        result:
          Jido.Joi.object(%{
            iterations: Jido.Joi.integer() |> Jido.Joi.min(0),
            state: @state_schema
          })
      })

  flow do
    iterate "repair" do
      state @state_schema, initial: %{missing: input(:missing), repairs: 0}

      action Jido.Examples.BoundedIteration.Repair
      params %{current: state(), repair_size: input(:repair_size)}

      update body_result()
      while state(:missing) > 0
      max_iterations 3
    end

    output %{result: result("repair")}
  end
end
