defmodule JidoTest.Authoring.Topology.Fixtures.Minimal do
  use Jido.Topology, name: "authoring_minimal"

  topology do
    metadata %{"suite" => "topology"}

    agents do
      agent :worker, JidoTest.Authoring.Topology.Fixtures.Worker,
        initial_state: %{label: "single"}
    end
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.KeywordMinimal do
  use Jido.Topology,
    name: "authoring_minimal",
    metadata: %{"suite" => "topology"},
    agents: [
      %{
        key: :worker,
        module: JidoTest.Authoring.Topology.Fixtures.Worker,
        initial_state: %{label: "single"}
      }
    ]
end
