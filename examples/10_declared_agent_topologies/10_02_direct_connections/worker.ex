defmodule Jido.Examples.Topology.PipelineWorker do
  @moduledoc "Commits the work result and explicitly emits completion."
  use Jido.Agent, name: "topology_pipeline_worker"

  state do
    schema Jido.Joi.object(%{total: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    route "examples.topology.pipeline.request" do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
        context: context do
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
