defmodule JidoTest.Authoring.Topology.Fixtures.Child do
  use Jido.Topology, name: "authoring_child"

  topology do
    schema Zoi.object(%{label: Zoi.string()})

    agents do
      agent :worker, JidoTest.Authoring.Topology.Fixtures.Worker,
        initial_state: %{label: input(:label)}
    end

    imports do
      bus :events
    end

    connections do
      subscribe :worker, to: :events, path: "authoring.work"
    end

    exports do
      agent :public_worker, from: :worker
    end
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.Nested do
  use Jido.Topology, name: "authoring_nested"

  topology do
    schema Zoi.object(%{label: Zoi.string() |> Zoi.default("nested")})

    agents do
      agent :observer, JidoTest.Authoring.Topology.Fixtures.Worker,
        depends_on: [ref(:team, :public_worker)]
    end

    resources do
      bus :events
    end

    topologies do
      include :team, JidoTest.Authoring.Topology.Fixtures.Child do
        inputs %{label: input(:label)}
        bind :events, to: :events
      end
    end
  end
end
