Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("durable_ingestion.ex", __DIR__)
Code.require_file("index.ex", __DIR__)

defmodule Jido.Examples.RAG.DurableIngestionTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.RAG.DurableIngestion
  alias DurableIngestion.{EmbedAndPlan, Index, LoadAndChunk}
  alias Jido.Examples.Support.OfflineInferenceClient

  test "refresh recovery retries a lost acknowledgement and rejects a stale revision" do
    {jido, child} = durable_instance()
    start_supervised!(child)
    index = start_supervised!(Index)

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

    # The application submits the update through its index port. The adapter
    # keeps the same plan and acknowledgement under the revision key.
    assert {:ok, loaded} = Jido.Exec.run(LoadAndChunk, request.data)
    context = %{jido_ai_inference_client: OfflineInferenceClient}
    assert {:ok, plan} = Jido.Exec.run(EmbedAndPlan, %{loaded: loaded}, context)
    assert {:error, :acknowledgement_lost} = Index.apply_plan(index, plan)

    assert :ok = stop_supervised(jido)
    start_supervised!(child)
    assert {:ok, %Status{state: :waiting, waits: [%{id: ^wait_id}]}} = Durable.status(jido, ref)

    assert {:ok, acknowledgement} = Index.apply_plan(index, plan)
    assert map_size(Index.revisions(index)) == 1

    stale = acknowledgement_signal(%{acknowledgement | revision: 1})
    assert {:error, _reason} = Durable.signal(jido, ref, wait_id, stale, now: 2_000)
    assert {:ok, %Status{state: :waiting}} = Durable.status(jido, ref)

    committed = acknowledgement_signal(acknowledgement)

    assert {:ok, %Status{state: :completed}} =
             Durable.signal(jido, ref, wait_id, committed, now: 2_000)

    assert {:ok, result} = Durable.result(jido, ref)
    assert Map.take(result, Map.keys(plan)) == plan
    assert result.status == :committed
    assert result.idempotency_key == "policy-1:2"
    assert result.delete_ids == ["policy-1:r1:c0"]
    assert Enum.map(result.upserts, & &1.id) == ["policy-1:r2:c0", "policy-1:r2:c1"]
    assert Enum.all?(result.upserts, &(length(&1.embedding) == 2))
    assert result.acknowledgement.index_revision == 41
  end

  defp acknowledgement_signal(data) do
    Jido.Signal.new!("examples.rag.index.committed", data, source: "/examples/rag/index")
  end

  defp durable_instance do
    suffix = System.unique_integer([:positive])
    jido = :"durable_rag_ingestion_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    child =
      Supervisor.child_spec(
        {Jido, name: jido, namespace: "examples/rag/ingestion/#{suffix}", persistence: persistence},
        id: jido
      )

    {jido, child}
  end
end
