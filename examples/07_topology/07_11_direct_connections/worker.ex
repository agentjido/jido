defmodule Jido.Examples.Topology.PipelineWorker do
  @moduledoc "Commits the work result and explicitly emits completion."
  use Jido.Agent, name: "topology_pipeline_worker"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    route "examples.topology.pipeline.request" do
      action %{value: value}, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        output =
          Jido.Signal.new!("examples.topology.pipeline.completed", %{value: value * 2},
            source: "/examples/topology/pipeline_worker"
          )

        {:ok, %{context.agent_state | total: context.agent_state.total + value * 2},
         [Jido.Agent.Directive.emit(output)]}
      end
    end
  end
end
