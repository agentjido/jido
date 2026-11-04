defmodule Jido.Examples.SequentialFlow do
  @moduledoc "A typed Flow produces one complete candidate; the Server commits it once."
  use Jido.Agent, name: "workflow_sequential_agent"

  state do
    schema Jido.Joi.object(%{
             value: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.max(100) |> Jido.Joi.default(0),
             label: Jido.Joi.string() |> Jido.Joi.default("kept")
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.sequential", Jido.Examples.SequentialFlow.Pipeline, as: :double_value
  end
end

defmodule Jido.Examples.SequentialFlow.Finish do
  @moduledoc false

  use Jido.Action,
    name: "workflow_finish",
    schema:
      Jido.Joi.object(%{
        value: Jido.Joi.integer(),
        failure: Jido.Joi.enum([:none, :middle, :output, :candidate])
      })

  @impl true
  def run(input, context) do
    value =
      case input.failure do
        :output -> -1
        :candidate -> 101
        _ -> input.value
      end

    {:ok, %{value: value, label: context.agent_state.label}}
  end
end

defmodule Jido.Examples.SequentialFlow.Pipeline do
  @moduledoc "Input, result dependencies, a control dependency, and output validation."

  use Jido.Flow,
    name: "workflow_sequential",
    schema:
      Jido.Joi.object(%{
        value: Jido.Joi.integer() |> Jido.Joi.min(0),
        failure: Jido.Joi.enum([:none, :middle, :output, :candidate]) |> Jido.Joi.default(:none)
      }),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.min(0), label: Jido.Joi.string()})

  flow do
    step "double", value <- input(:value) do
      {:ok, %{value: value * 2}}
    end

    step "gate", failure <- input(:failure), needs: ["double"] do
      if failure == :middle,
        do: {:error, Jido.Error.execution_error("gate rejected", stage: :gate)},
        else: {:ok, %{checked: true}}
    end

    step "finish",
      action: Jido.Examples.SequentialFlow.Finish,
      params: %{value: result("double", :value), failure: input(:failure)},
      needs: ["gate"]

    output result("finish")
  end
end
