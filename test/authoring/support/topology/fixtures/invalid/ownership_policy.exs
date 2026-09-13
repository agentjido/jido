defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.OwnershipPolicy do
  use Jido.Topology, name: "invalid_ownership_policy"

  topology do
    agents do
      agent :parent, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :child, JidoTest.Authoring.Topology.Fixtures.Worker
    end

    relationships do
      owns :parent, :child, on_parent_exit: :restart
    end
  end
end
