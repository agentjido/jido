defmodule Jido.Examples.Persistence.PortableCheckpoint do
  @moduledoc "An Agent whose persisted payload must contain portable values only."
  use Jido.Agent, name: "examples_portable_checkpoint"

  agent do
    schema Zoi.object(%{payload: Zoi.map() |> Zoi.default(%{})})
  end
end
