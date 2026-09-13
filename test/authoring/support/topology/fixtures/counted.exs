defmodule JidoTest.Authoring.Topology.Fixtures.Counted do
  use Jido.Topology, name: "authoring_counted"

  topology do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(2)})

    agents do
      agent :observer, JidoTest.Authoring.Topology.Fixtures.Worker, depends_on: [:workers]

      group :workers, JidoTest.Authoring.Topology.Fixtures.Worker do
        count input(:count)
        initial_state %{value: member(:index)}
      end
    end

    startup do
      max_agents 3
    end
  end
end
