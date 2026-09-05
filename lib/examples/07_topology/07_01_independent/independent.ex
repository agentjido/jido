defmodule Jido.Examples.Topology.Independent do
  @moduledoc "Two independent Agents with distinct initial state."
  use Jido.Topology, name: "independent"

  agents do
    agent :left, Jido.Examples.Topology.Cell do
      initial_state %{label: "left"}
    end

    agent :right, Jido.Examples.Topology.Cell do
      initial_state %{label: "right"}
    end
  end
end
