defmodule Jido.Examples.Research.DataDefinedTopology.DirectDSL do
  @moduledoc "A neutral definition selected in the Topology DSL."
  use Jido.Topology, name: "direct_data_member_dsl"

  topology do
    agents do
      agent :alice,
        definition: Jido.Examples.Research.DataDefinedTopology.Definitions.direct(:alice)

      group :workers,
        definition: Jido.Examples.Research.DataDefinedTopology.Definitions.direct(:bob),
        count: 2
    end
  end
end
