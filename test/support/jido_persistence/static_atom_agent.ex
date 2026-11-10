defmodule Jido.Test.Persistence.StaticAtomAgent do
  @moduledoc false

  use Jido.Agent, name: "persistence_static_atom_probe"

  state do
    schema Jido.Joi.object(%{jido_static_persistence_probe: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end
end
