defmodule Jido.Examples.Topology.PipelineSink do
  @moduledoc "A stateless transform returns the receipt Signal without an Action."
  use Jido.Agent, name: "topology_pipeline_sink"

  routes do
    route "examples.topology.pipeline.completed", emits: ["examples.topology.pipeline.receipt"] do
      transform %Jido.Signal{data: %{value: value}} do
        Jido.Signal.new("examples.topology.pipeline.receipt", %{value: value},
          source: "/examples/topology/pipeline_sink"
        )
      end
    end
  end
end
