defmodule Jido.Examples.Persistence.CheckpointIdentity do
  @moduledoc "An Agent used to show that a checkpoint cannot change durable identity."

  alias Jido.Joi

  use Jido.Agent, name: "examples_checkpoint_identity"

  state do
    schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
  end
end
