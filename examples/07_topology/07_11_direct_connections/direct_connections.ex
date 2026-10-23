defmodule Jido.Examples.Topology.DirectConnections do
  @moduledoc "Explicit outputs connect a root, a worker, and a receipt Agent."
  use Jido.Agent, name: "topology_direct_connections"

  agent do
    schema Zoi.object(%{completed: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/topology/direct_connections"

    forward "examples.topology.pipeline.request", to: agent(:worker)

    route "examples.topology.pipeline.receipt", as: :receipt do
      action %{value: value}, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | completed: context.agent_state.completed + value}}
      end
    end
  end

  topology do
    agent :worker, Jido.Examples.Topology.PipelineWorker
    agent :sink, Jido.Examples.Topology.PipelineSink

    connections do
      connect "examples.topology.pipeline.completed", from: :worker, to: :sink
      connect "examples.topology.pipeline.receipt", from: :sink, to: :root
    end
  end
end
