defmodule Jido.Examples.Topology.Hierarchy do
  @moduledoc "A coordinator owns a team leader, which owns three workers."
  use Jido.Topology, name: "hierarchy"

  agents do
    agent :coordinator, Jido.Examples.Topology.Cell
    agent :leader, Jido.Examples.Topology.Cell

    group :workers, Jido.Examples.Topology.Cell do
      count 3
    end
  end

  relationships do
    owns :coordinator, :leader

    owns :leader, :workers do
      on_parent_exit :stop
    end
  end
end
