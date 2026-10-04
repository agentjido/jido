defmodule Jido.Examples.Research.ChildTopologyRuntime.Worker do
  @moduledoc "A member with one normal command for the lazy runtime examples."
  use Jido.Agent, name: "child_runtime_worker"

  agent do
    schema Zoi.object(%{
             label: Zoi.string() |> Zoi.default("Worker"),
             total: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/research/child_runtime/member"

    route "examples.research.child_runtime.record", as: :record do
      action input, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | total: context.agent_state.total + input.value}}
      end
    end
  end
end
