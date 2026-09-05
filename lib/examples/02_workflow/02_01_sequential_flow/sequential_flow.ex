defmodule Jido.Examples.SequentialFlow.Finish do
  @moduledoc false
  use Jido.Action, name: "workflow_finish"

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, :finish, input)

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
  alias Jido.Examples.Workflow.Observation

  use Jido.Flow,
    name: "workflow_sequential",
    schema:
      Zoi.object(%{
        value: Zoi.integer() |> Zoi.min(0),
        failure: Zoi.enum([:none, :middle, :output, :candidate]) |> Zoi.default(:none)
      }),
    output_schema: Zoi.object(%{value: Zoi.integer() |> Zoi.min(0), label: Zoi.string()})

  flow do
    step "double" do
      action value <- input(:value) * 2, context: ctx do
        Observation.record(ctx, :double, %{value: value})
        {:ok, %{value: value}}
      end
    end

    step "gate",
         [value <- result("double", :value), failure <- input(:failure), ctx <- context()] do
      Observation.record(ctx, :gate, %{value: value, failure: failure})

      if failure == :middle,
        do: {:error, Jido.Action.Error.execution_error("gate rejected", stage: :gate)},
        else: {:ok, %{checked: true}}
    end

    step "finish",
      action: Jido.Examples.SequentialFlow.Finish,
      params: %{value: result("double", :value), failure: input(:failure)},
      after: ["gate"]

    output result("finish")
  end
end

defmodule Jido.Examples.SequentialFlow do
  @moduledoc "A typed Flow produces one complete candidate; the Server commits it once."
  use Jido.Agent, name: "workflow_sequential_agent"

  agent do
    schema Zoi.object(%{
             value: Zoi.integer() |> Zoi.min(0) |> Zoi.max(100) |> Zoi.default(0),
             label: Zoi.string() |> Zoi.default("kept")
           })
  end

  routes do
    signal_source "/workflow"

    route "workflow.sequential", Jido.Examples.SequentialFlow.Pipeline do
      define :double_value, args: [:value, {:optional, :failure}]
    end
  end
end
