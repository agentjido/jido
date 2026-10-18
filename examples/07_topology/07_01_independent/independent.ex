defmodule Jido.Examples.Topology.Independent do
  @moduledoc "Two named members keep separate state under one owning Agent."
  use Jido.Agent, name: "topology_independent"

  topology do
    agent :left, Jido.Examples.Topology.Cell do
      initial_state %{label: "left"}
    end

    agent :right, Jido.Examples.Topology.Cell do
      initial_state %{label: "right"}
    end
  end
end
