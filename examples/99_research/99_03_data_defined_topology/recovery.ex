defmodule Jido.Examples.Research.DataDefinedTopology.Recovery do
  @moduledoc "Declares the same Agent and Bus for module and data recovery cases."

  alias Jido.Topology
  alias Jido.Examples.Research.DataDefinedTopology.Definitions

  def definition(source) do
    Topology.new(
      name: "authoring_recovery",
      agents: [Definitions.entry(:worker, source, %{total: 2})],
      resources: [%{key: :events, kind: :bus}],
      connections: [%{agent: :worker, to: :events, path: Definitions.path(source)}],
      startup: [retry_interval: 10]
    )
  end
end
