Code.require_file("nested.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.Fixtures.Repeated do
  use Jido.Topology, name: "authoring_repeated"

  topology do
    schema Zoi.object(%{label: Zoi.string() |> Zoi.default("left")})

    resources do
      bus :events
    end

    topologies do
      include "team/a", JidoTest.Authoring.Topology.Fixtures.Child do
        inputs %{label: input(:label)}
        bind :events, to: :events
      end

      include "team%2Fa", JidoTest.Authoring.Topology.Fixtures.Child do
        inputs %{label: "right"}
        bind :events, to: :events
      end
    end
  end
end
