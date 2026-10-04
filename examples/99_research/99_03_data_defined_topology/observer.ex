defmodule Jido.Examples.Research.DataDefinedTopology.Observer do
  @moduledoc "An existing topology member with a total that must survive an update."
  use Jido.Agent, name: "data_topology_observer"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/research/data_defined_topology"

    route "examples.research.data_defined_topology.observer.record",
          Jido.Examples.Research.DataDefinedTopology.Record,
          as: :record
  end
end
