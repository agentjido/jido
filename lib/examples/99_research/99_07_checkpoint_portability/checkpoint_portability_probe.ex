defmodule Jido.Examples.CheckpointPortabilityProbe do
  @moduledoc "PERSIST-02: loaded checkpoints must exclude process-local runtime values."
  use Jido.Agent, name: "research_checkpoint_portability"

  agent do
    schema Zoi.object(%{payload: Zoi.map() |> Zoi.default(%{})})
  end

  @doc "Inserts a payload through storage to exercise load validation independently of save."
  def store_payload(store, id, payload) do
    with :ok <- Jido.Persistence.save_agent(store, new!(id: id), revision: 3) do
      Jido.Examples.PersistenceProbeStore.rewrite_record(store, __MODULE__, id, fn record ->
        put_in(record.checkpoint.state.payload, payload)
      end)
    end
  end
end
