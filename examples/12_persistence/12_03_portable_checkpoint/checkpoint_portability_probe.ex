defmodule Jido.Examples.Persistence.PortableCheckpoint do
  @moduledoc "An Agent whose persisted payload must contain portable values only."

  alias Jido.Joi

  use Jido.Agent, name: "examples_portable_checkpoint"

  state do
    schema Joi.object(%{payload: Joi.map() |> Joi.default(%{})})
  end
end
