defmodule JidoTest.Authoring.Topology.Fixtures.Combined do
  use Jido.Topology,
    name: "authoring_combined",
    extensions: [JidoTest.Authoring.Topology.Fixtures.Roles]

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    metadata %{"kind" => "owner"}
  end

  routes do
    signal_source "/authoring/owner"

    route "owner.set", JidoTest.Authoring.Topology.Fixtures.SetValue do
      define :set, args: [:value]
    end
  end

  topology do
    metadata %{"kind" => "topology"}

    agents do
      role(:worker, JidoTest.Authoring.Topology.Fixtures.Worker)
    end
  end
end
