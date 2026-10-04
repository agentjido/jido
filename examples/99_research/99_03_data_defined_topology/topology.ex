defmodule Jido.Examples.Research.DataDefinedTopology.Topology do
  @moduledoc "The fixed DSL definition for a topology that will receive stored Agents."
  use Jido.Topology, name: "hybrid_data_defined_topology"

  topology do
    agents do
      agent :observer, Jido.Examples.Research.DataDefinedTopology.Observer
    end
  end
end
