defmodule Jido.Examples.CheckpointIdentityProbe do
  @moduledoc "PERSIST-01: a loaded Agent must have the identity requested by the caller."
  use Jido.Agent, name: "research_checkpoint_identity"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  @doc "Stores a valid envelope with a different Agent ID inside the checkpoint."
  def store_mismatched_checkpoint(store, requested_id, checkpoint_id) do
    agent = new!(id: requested_id, state: %{count: 7})

    with :ok <- Jido.Persistence.save_agent(store, agent, revision: 3) do
      Jido.Examples.PersistenceProbeStore.rewrite_record(
        store,
        __MODULE__,
        requested_id,
        fn record ->
          put_in(record.checkpoint.id, checkpoint_id)
        end
      )
    end
  end
end
