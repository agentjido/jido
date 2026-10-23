defmodule Jido.Examples.Persistence.CheckpointIdentity do
  @moduledoc "An Agent used to show that a checkpoint cannot change durable identity."
  use Jido.Agent, name: "examples_checkpoint_identity"

  state do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end
end
