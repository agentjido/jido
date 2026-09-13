defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.MissingBinding do
  use Jido.Topology, name: "invalid_missing_binding"

  topology do
    topologies do
      include :team, JidoTest.Authoring.Topology.Fixtures.Child, inputs: %{label: "child"}
    end
  end
end
