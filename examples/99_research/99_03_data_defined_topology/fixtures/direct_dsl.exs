defmodule Jido.Examples.Research.DataDefinedTopology.DirectDSL do
  @moduledoc "An unsupported neutral value in the current DSL member argument."
  use Jido.Topology, name: "direct_data_member_dsl"

  topology do
    agents do
      agent :alice, Jido.Examples.Research.DataDefinedTopology.Definitions.direct(:alice)
    end
  end
end
