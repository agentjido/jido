defmodule Jido.Examples.ParallelJoin do
  @moduledoc "Two independent Flow branches join before one Agent commit."
  use Jido.Agent, name: "workflow_parallel_agent"

  state do
    schema Jido.Joi.object(%{result: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.parallel", Jido.Examples.ParallelJoin.Pipeline, as: :fetch_pair
  end
end

defmodule Jido.Examples.ParallelJoin.Fetch do
  @moduledoc false

  use Jido.Action,
    name: "workflow_parallel_fetch",
    schema:
      Jido.Joi.object(%{
        side: Jido.Joi.enum([:left, :right]),
        value: Jido.Joi.integer(),
        fail: Jido.Joi.enum([:none, :left, :right])
      })

  @impl true
  def run(input, context) do
    if input.side == input.fail do
      {:error, Jido.Error.execution_error("retriever failed", source: input.side)}
    else
      {:ok, %{side: input.side, value: input.value, request: context[:request]}}
    end
  end
end

defmodule Jido.Examples.ParallelJoin.Pipeline do
  @moduledoc "Two independent reads and one join with inferred dependencies."

  use Jido.Flow,
    name: "workflow_parallel",
    schema:
      Jido.Joi.object(%{
        value: Jido.Joi.integer(),
        fail: Jido.Joi.enum([:none, :left, :right]) |> Jido.Joi.default(:none)
      }),
    output_schema:
      Jido.Joi.object(%{
        result: Jido.Joi.object(%{left: Jido.Joi.map(), right: Jido.Joi.map()})
      })

  flow do
    step "left",
      action: Jido.Examples.ParallelJoin.Fetch,
      params: %{side: :left, value: input(:value), fail: input(:fail)}

    step "right",
      action: Jido.Examples.ParallelJoin.Fetch,
      params: %{side: :right, value: input(:value), fail: input(:fail)}

    step "join", [left <- result("left"), right <- result("right")] do
      joined = %{left: left, right: right}
      {:ok, %{result: joined}}
    end

    output result("join")
  end
end
