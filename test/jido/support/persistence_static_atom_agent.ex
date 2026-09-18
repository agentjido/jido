defmodule JidoTest.Persistence.StaticAtomAgent do
  @moduledoc false

  use Jido.Agent, name: "persistence_static_atom_probe"

  agent do
    schema Zoi.object(%{jido_static_persistence_probe: Zoi.integer() |> Zoi.default(0)})
  end
end
