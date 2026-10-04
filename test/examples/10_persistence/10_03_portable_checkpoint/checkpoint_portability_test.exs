defmodule JidoTest.Examples.Persistence.PortableCheckpointTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.Persistence.PortableCheckpoint, as: Probe
  alias Jido.Persistence
  alias JidoTest.Persistence.ProbeStore

  test "load rejects a process handle inserted into a stored checkpoint" do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    id = unique_id("example-checkpoint-portability")
    assert :ok = store_payload(store, id, %{job: %{worker: self()}})

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :non_portable_term,
                path: [:record, :checkpoint, :state, :payload, :job, :worker]
              }
            }} = Persistence.load_agent(store, Probe, id, namespace: "persistence-probe")
  end

  defp store_payload(store, id, payload) do
    assert :ok =
             Persistence.save_agent(store, Probe.new!(id: id),
               namespace: "persistence-probe",
               revision: 3
             )

    ProbeStore.rewrite_record(store, id, fn record ->
      put_in(record.checkpoint.state.payload, payload)
    end)
  end
end
