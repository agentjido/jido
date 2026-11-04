defmodule Jido.Examples.Persistence.PortableCheckpoint do
  @moduledoc "An Agent whose persisted payload must contain portable values only."
  use Jido.Agent, name: "examples_portable_checkpoint"

  state do
    schema Jido.Joi.object(%{payload: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end
end
