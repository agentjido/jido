defmodule Jido.Examples.Topology.PipelineWorker do
  @moduledoc "Commits the work result and explicitly emits completion."

  alias Jido.Joi

  use Jido.Agent, name: "topology_pipeline_worker"

  state do
    schema Joi.object(%{total: Joi.integer() |> Joi.default(0)})
  end

  routes do
    route "examples.topology.pipeline.request" do
      action %{value: value},
        schema: Joi.object(%{value: Joi.integer()}),
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
