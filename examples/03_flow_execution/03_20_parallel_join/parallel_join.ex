defmodule Jido.Examples.ParallelJoin do
  @moduledoc "Two independent Flow branches join before one Agent commit."

  alias Jido.Joi

  use Jido.Agent, name: "workflow_parallel_agent"

  state do
    schema Joi.object(%{result: Joi.map() |> Joi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.parallel", Jido.Examples.ParallelJoin.Pipeline, as: :fetch_pair
  end
end

defmodule Jido.Examples.ParallelJoin.Fetch do
  @moduledoc false

  alias Jido.Joi

  use Jido.Action,
    name: "workflow_parallel_fetch",
    schema:
      Joi.object(%{
        side: Joi.enum([:left, :right]),
        value: Joi.integer(),
        fail: Joi.enum([:none, :left, :right])
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

  alias Jido.Joi

  use Jido.Flow,
    name: "workflow_parallel",
    schema:
      Joi.object(%{
        value: Joi.integer(),
        fail: Joi.enum([:none, :left, :right]) |> Joi.default(:none)
      }),
    output_schema:
      Joi.object(%{
        result: Joi.object(%{left: Joi.map(), right: Joi.map()})
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
