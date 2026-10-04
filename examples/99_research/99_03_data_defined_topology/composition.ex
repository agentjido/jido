defmodule Jido.Examples.Research.DataDefinedTopology.Composition.Child do
  @moduledoc "A reusable DSL Topology with one exported Agent."
  use Jido.Topology, name: "authoring_child"

  topology do
    agents do
      agent :worker, Jido.Examples.Research.DataDefinedTopology.Worker, initial_state: %{total: 2}
    end

    exports do
      agent :worker, from: :worker
    end
  end
end

defmodule Jido.Examples.Research.DataDefinedTopology.Composition.Parent do
  @moduledoc "A DSL Topology that includes a reusable child component."
  use Jido.Topology, name: "authoring_parent"

  topology do
    topologies do
      include :team, Jido.Examples.Research.DataDefinedTopology.Composition.Child
    end
  end
end

defmodule Jido.Examples.Research.DataDefinedTopology.Composition do
  @moduledoc "Combines DSL and data parent and child Topologies."

  alias Jido.Topology
  alias Jido.Examples.Research.DataDefinedTopology.Definitions
  alias __MODULE__.{Child, Parent}

  def child(source), do: child(:data, source)

  def child(:dsl, source) do
    [agent] = Child.topology().agents
    Topology.new(%{Child.topology() | agents: [%{agent | module: source}]})
  end

  def child(:data, source) do
    Topology.new(
      name: "authoring_child",
      agents: [Definitions.entry(:worker, source, %{total: 2})],
      exports: [%{key: :worker, kind: :agent, from: :worker}]
    )
  end

  def parent(:dsl, child) do
    [include] = Parent.topology().includes
    Topology.new(%{Parent.topology() | includes: [%{include | topology: child}]})
  end

  def parent(:data, child),
    do: Topology.new(name: "authoring_parent", includes: [%{key: :team, topology: child}])

  def dsl_child, do: Child
end
