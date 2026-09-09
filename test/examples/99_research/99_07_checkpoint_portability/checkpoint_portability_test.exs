defmodule JidoTest.Examples.CheckpointPortabilityTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.CheckpointPortabilityProbe, as: Probe
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Persistence

  test "load rejects a process handle inserted into a stored checkpoint" do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    id = unique_id("example-checkpoint-portability")
    assert :ok = Probe.store_payload(store, id, %{job: %{worker: self()}})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:record, :checkpoint, :state, :payload, :job, :worker]
              }
            }} = Persistence.load_agent(store, Probe, id)
  end
end
