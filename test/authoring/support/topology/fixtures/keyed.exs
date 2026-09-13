defmodule JidoTest.Authoring.Topology.Fixtures.Keyed do
  use Jido.Topology, name: "authoring_keyed"

  topology do
    schema Zoi.object(%{members: Zoi.list(Zoi.object(%{key: Zoi.string(), label: Zoi.string()}))})

    agents do
      group :workers, JidoTest.Authoring.Topology.Fixtures.Worker do
        members input(:members)
        key_by :key
        initial_state %{label: member(:label)}
      end
    end
  end
end
