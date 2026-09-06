defmodule Jido.Examples.ParallelJoin.Fetch do
  @moduledoc false
  use Jido.Action, name: "workflow_parallel_fetch"

  def run(input, context) do
    Jido.Examples.Workflow.Observation.record(context, input.side, input)

    if input.side == input.fail do
      {:error, Jido.Action.Error.execution_error("retriever failed", source: input.side)}
    else
      {:ok, %{side: input.side, value: input.value, request: context[:request]}}
    end
  end
end

defmodule Jido.Examples.ParallelJoin.Pipeline do
  @moduledoc "Two independent reads and one join with inferred dependencies."
  alias Jido.Examples.Workflow.Observation

  use Jido.Flow,
    name: "workflow_parallel",
    schema:
      Zoi.object(%{
        value: Zoi.integer(),
        fail: Zoi.enum([:none, :left, :right]) |> Zoi.default(:none)
      })

  flow do
    step "left",
      action: Jido.Examples.ParallelJoin.Fetch,
      params: %{side: :left, value: input(:value), fail: input(:fail)}

    step "right",
      action: Jido.Examples.ParallelJoin.Fetch,
      params: %{side: :right, value: input(:value), fail: input(:fail)}

    step "join" do
      action [left <- result("left"), right <- result("right")], context: ctx do
        joined = %{left: left, right: right}
        Observation.record(ctx, :join, joined)
        {:ok, %{result: joined}}
      end
    end

    output result("join")
  end
end

defmodule Jido.Examples.ParallelJoin do
  @moduledoc "Concurrent Flow work remains within one cancellable Agent Turn."
  use Jido.Agent, name: "workflow_parallel_agent"

  agent do
    schema Zoi.object(%{result: Zoi.map() |> Zoi.default(%{})})
  end

  routes do
    signal_source "/workflow"

    route "workflow.parallel", Jido.Examples.ParallelJoin.Pipeline do
      define :fetch_pair, args: [:value, {:optional, :fail}]
    end
  end
end
