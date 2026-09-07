defmodule JidoCoreBench.TopologyCases do
  @moduledoc false

  alias Jido.Examples.Topology.Cell
  alias Jido.Topology
  alias Jido.Topology.Builder
  alias JidoCoreBench.Fixtures, as: F

  def workloads(sizes) do
    for base <- sizes, operation <- [:builder, :definition] do
      size = base * 16

      F.checked(
        "topology/#{operation}/agents_#{size}",
        fn _context -> setup(operation, size) end,
        fn prepared -> run(operation, prepared, size) end,
        fn {:ok, definition} -> F.equal!(length(definition.agents), size) end
      )
    end
  end

  defp setup(:builder, _size), do: nil

  defp setup(:definition, size) do
    %{
      name: "topology-bench",
      agents: for(index <- 1..size, do: %{key: "agent-#{index}", module: Cell})
    }
  end

  defp run(:builder, _prepared, size) do
    Enum.reduce(1..size, Builder.new(name: "topology-bench"), fn index, builder ->
      Builder.agent(builder, "agent-#{index}", Cell)
    end)
    |> Builder.build()
  end

  defp run(:definition, attrs, _size), do: Topology.new(attrs)
end
