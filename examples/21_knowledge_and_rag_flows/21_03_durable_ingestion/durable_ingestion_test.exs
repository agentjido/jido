Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("durable_ingestion.ex", __DIR__)

defmodule Jido.Examples.RAG.DurableIngestionTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.RAG.DurableIngestion
  alias Jido.Examples.Support.OfflineInferenceClient

  test "a refresh plan survives a wait and completes from index acknowledgement" do
    jido = start_durable_jido()

    {:ok, request} =
      Jido.Signal.new(
        "examples.rag.document.refresh",
        %{
          document: %{
            id: "policy-1",
            revision: 2,
            content: "Reports are retained for 30 days.\n\nDelete expired reports each night."
          },
          previous_chunk_ids: ["policy-1:r1:c0"]
        },
        source: "/examples/rag"
      )

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(jido, DurableIngestion, request,
               context: %{jido_ai_inference_client: OfflineInferenceClient},
               now: 1_000
             )

    {:ok, committed} =
      Jido.Signal.new(
        "examples.rag.index.committed",
        %{document_id: "policy-1", revision: 2, index_revision: 41},
        source: "/examples/rag/index"
      )

    assert {:ok, %Status{state: :completed}} =
             Durable.signal(jido, ref, wait_id, committed, now: 2_000)

    assert {:ok, result} = Durable.result(jido, ref)
    assert result.status == :committed
    assert result.idempotency_key == "policy-1:2"
    assert result.delete_ids == ["policy-1:r1:c0"]
    assert Enum.map(result.upserts, & &1.id) == ["policy-1:r2:c0", "policy-1:r2:c1"]
    assert Enum.all?(result.upserts, &(length(&1.embedding) == 2))
    assert result.acknowledgement.index_revision == 41
  end

  defp start_durable_jido do
    suffix = System.unique_integer([:positive])
    jido = :"durable_rag_ingestion_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: jido, namespace: "examples/rag/ingestion/#{suffix}", persistence: persistence},
      id: jido
    )

    jido
  end
end
