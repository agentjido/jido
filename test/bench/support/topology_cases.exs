defmodule JidoCoreBench.TopologyCases do
  @moduledoc false

  alias Jido.Examples.Topology.Cell
  alias Jido.Topology
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes) do
    for base <- sizes do
      size = base * 16

      F.checked(
        "topology/definition/agents_#{size}",
        fn _context -> setup(size) end,
        fn prepared -> Topology.new(prepared) end,
        fn {:ok, definition} -> F.equal!(length(definition.agents), size) end
      )
    end
  end

  defp setup(size) do
    %{
      name: "topology-bench",
      agents: for(index <- 1..size, do: %{key: "agent-#{index}", module: Cell})
    }
  end
end
