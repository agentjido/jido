defmodule JidoTest.Authoring.Topology.Fixtures.DeepLeaf do
  use Jido.Topology, name: "authoring_deep_leaf"

  topology do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.min(0), label: Zoi.string()})

    agents do
      agent :leader, JidoTest.Authoring.Topology.Fixtures.Worker,
        initial_state: %{label: input(:label)}

      group :workers, JidoTest.Authoring.Topology.Fixtures.Worker do
        count input(:count)
        initial_state %{label: input(:label), value: member(:index)}
        depends_on [:leader]
      end
    end

    imports do
      bus :events
    end

    connections do
      subscribe :workers, to: :events, path: "authoring.work"
    end

    exports do
      agent :leader, from: :leader
      group :workers, from: :workers
      bus :events, from: :events
    end

    startup do
      max_agents 3
    end
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.DeepRegion do
  use Jido.Topology, name: "authoring_deep_region"

  topology do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(1),
             label: Zoi.string() |> Zoi.default("region")
           })

    imports do
      bus :events
    end

    topologies do
      include :team, JidoTest.Authoring.Topology.Fixtures.DeepLeaf do
        inputs %{count: input(:count), label: input(:label)}
        bind :events, to: :events
      end
    end

    exports do
      agent :leader, from: ref(:team, :leader)
      group :workers, from: ref(:team, :workers)
      bus :events, from: ref(:team, :events)
    end
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.Deep do
  use Jido.Topology, name: "authoring_deep"

  topology do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(2),
             label: Zoi.string() |> Zoi.default("deep")
           })

    agents do
      agent :observer, JidoTest.Authoring.Topology.Fixtures.Worker,
        depends_on: [ref(:region, :leader), ref(:region, :workers)]
    end

    resources do
      bus :events
    end

    connections do
      subscribe :observer, to: ref(:region, :events), path: "authoring.work"
    end

    topologies do
      include :region, JidoTest.Authoring.Topology.Fixtures.DeepRegion do
        inputs %{count: input(:count), label: input(:label)}
        bind :events, to: :events
      end
    end

    startup do
      max_agents 5
    end
  end
end
