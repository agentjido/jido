defmodule Jido.Examples.BoundedIteration do
  @moduledoc "Local repair state is separate from the Agent's committed state."

  alias Jido.Joi

  use Jido.Agent, name: "workflow_iteration_agent"

  state do
    schema Joi.object(%{result: Joi.map() |> Joi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.iteration", Jido.Examples.BoundedIteration.Pipeline, as: :repair
  end
end

defmodule Jido.Examples.BoundedIteration.Repair do
  @moduledoc false
  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_iteration_repair",
    schema:
      Joi.object(%{
        current: Joi.object(%{missing: Joi.integer(), repairs: Joi.integer()}),
        repair_size: Joi.integer() |> Joi.min(1)
      })

  flow do
    step "normalize", params <- input() do
      {:ok, %{missing: params.current.missing - params.repair_size, repairs: params.current.repairs}}
    end

    step "record", current <- result("normalize") do
      {:ok, %{current | repairs: current.repairs + 1}}
    end

    output result("record")
  end
end

defmodule Jido.Examples.BoundedIteration.Pipeline do
  @moduledoc "A while loop validates each replacement state and permits at most three repairs."

  alias Jido.Joi

  @state_schema Joi.object(%{
                  missing: Joi.integer() |> Joi.min(0),
                  repairs: Joi.integer() |> Joi.min(0)
                })

  use Jido.Flow,
    name: "workflow_iteration",
    schema:
      Joi.object(%{
        missing: Joi.integer() |> Joi.min(0),
        repair_size: Joi.integer() |> Joi.min(1) |> Joi.default(1)
      }),
    output_schema:
      Joi.object(%{
        result:
          Joi.object(%{
            iterations: Joi.integer() |> Joi.min(0),
            state: @state_schema
          })
      })

  flow do
    iterate "repair" do
      state @state_schema, initial: %{missing: input(:missing), repairs: 0}

      flow Jido.Examples.BoundedIteration.Repair
      params %{current: state(), repair_size: input(:repair_size)}

      update body_result()
      while state(:missing) > 0
      max_iterations 3
    end

    output %{result: result("repair")}
  end
end
