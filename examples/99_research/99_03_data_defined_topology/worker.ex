defmodule Jido.Examples.Research.DataDefinedTopology.Worker do
  @moduledoc "The DSL Agent control for the equivalent data Agent examples."
  use Jido.Agent, name: "data_topology_worker"

  agent do
    schema Zoi.object(%{
             label: Zoi.string() |> Zoi.default("Worker"),
             total: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Research.DataDefinedTopology.RecordCount
  end

  routes do
    signal_source "/examples/research/data_defined_topology"

    route "examples.research.data_defined_topology.worker.record",
          Jido.Examples.Research.DataDefinedTopology.Record,
          as: :record
  end
end
