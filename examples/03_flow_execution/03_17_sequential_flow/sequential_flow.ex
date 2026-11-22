defmodule Jido.Examples.SequentialFlow do
  @moduledoc "A typed Flow produces one complete candidate; the Server commits it once."

  alias Jido.Joi

  use Jido.Agent, name: "workflow_sequential_agent"

  state do
    schema Joi.object(%{
             value: Joi.integer() |> Joi.min(0) |> Joi.max(100) |> Joi.default(0),
             label: Joi.string() |> Joi.default("kept")
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.sequential", Jido.Examples.SequentialFlow.Pipeline, as: :double_value
  end
end

defmodule Jido.Examples.SequentialFlow.Finish do
  @moduledoc false

  alias Jido.Joi

  use Jido.Action,
    name: "workflow_finish",
    schema:
      Joi.object(%{
        value: Joi.integer(),
        failure: Joi.enum([:none, :middle, :output, :candidate])
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

  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_sequential",
    schema:
      Joi.object(%{
        value: Joi.integer() |> Joi.min(0),
        failure: Joi.enum([:none, :middle, :output, :candidate]) |> Joi.default(:none)
      }),
    output_schema: Joi.object(%{value: Joi.integer() |> Joi.min(0), label: Joi.string()})

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
