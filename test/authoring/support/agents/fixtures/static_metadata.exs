defmodule JidoTest.Authoring.Agents.Fixtures.StaticMetadata do
  use Jido.Agent, name: "authoring_static_metadata"

  agent do
    schema Zoi.object(%{payload: Zoi.map() |> Zoi.default(%{})})
    metadata %{stamp: ~D[2026-09-13], values: {:ready, <<255>>, 1, 1.0}}
  end

  routes do
    route "metadata.inspect", JidoTest.Authoring.Agents.Fixtures.Noop
  end
end
