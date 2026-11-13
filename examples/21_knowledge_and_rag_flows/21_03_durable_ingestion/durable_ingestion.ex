defmodule Jido.Examples.RAG.DurableIngestion.LoadAndChunk do
  use Jido.Action, name: "example_rag_load_and_chunk"

  @impl true
  def run(%{document: document, previous_chunk_ids: previous_ids}, _context) do
    chunks =
      document.content
      |> String.split(~r/\n\n+/, trim: true)
      |> Enum.with_index()
      |> Enum.map(fn {text, index} ->
        %{
          id: "#{document.id}:r#{document.revision}:c#{index}",
          document_id: document.id,
          document_revision: document.revision,
          position: index,
          text: text
        }
      end)

    if chunks == [] do
      {:error, Jido.Error.validation_error("document produced no chunks")}
    else
      {:ok, %{document: document, chunks: chunks, delete_ids: previous_ids}}
    end
  end
end

defmodule Jido.Examples.RAG.DurableIngestion.EmbedAndPlan do
  use Jido.Action, name: "example_rag_embed_and_plan"

  @impl true
  def run(%{loaded: loaded}, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)

    with {:ok, vectors} <- client.embed("offline:embedding", Enum.map(loaded.chunks, & &1.text), []),
         true <- length(vectors) == length(loaded.chunks) do
      upserts =
        Enum.zip_with(loaded.chunks, vectors, fn chunk, vector ->
          Map.put(chunk, :embedding, vector)
        end)

      {:ok,
       %{
         document_id: loaded.document.id,
         revision: loaded.document.revision,
         upserts: upserts,
         delete_ids: loaded.delete_ids,
         idempotency_key: "#{loaded.document.id}:#{loaded.document.revision}",
         quality: %{all_chunks_embedded: true, chunk_count: length(upserts)}
       }}
    else
      false -> {:error, Jido.Error.validation_error("embedding count does not match chunk count")}
      {:error, reason} -> {:error, Jido.Error.execution_error("embedding failed", %{reason: reason})}
    end
  end
end

defmodule Jido.Examples.RAG.DurableIngestion.Finalize do
  use Jido.Action, name: "example_rag_finalize_ingestion"

  @impl true
  def run(%{plan: plan, commit: commit}, _context) do
    {:ok,
     Map.merge(plan, %{
       status: String.to_existing_atom(commit.selected),
       acknowledgement: commit.value
     })}
  end
end

defmodule Jido.Examples.RAG.DurableIngestion do
  use Jido.Flow,
    name: "example_durable_rag_ingestion",
    schema:
      Jido.Joi.object(%{
        document: Jido.Joi.map(),
        previous_chunk_ids: Jido.Joi.list(Jido.Joi.string())
      })

  alias Jido.Examples.RAG.DurableIngestion.{EmbedAndPlan, Finalize, LoadAndChunk}

  flow do
    step "load_chunk",
      action: LoadAndChunk,
      params: %{document: input(:document), previous_chunk_ids: input(:previous_chunk_ids)}

    step "embed_plan", action: EmbedAndPlan, params: %{loaded: result("load_chunk")}

    selection "commit" do
      await "committed",
        event: "examples.rag.index.committed",
        match: %{
          document_id: result("embed_plan", :document_id),
          revision: result("embed_plan", :revision)
        }

      timer "expired", after_ms: 60_000
    end

    step "finalize",
      action: Finalize,
      params: %{plan: result("embed_plan"), commit: result("commit")}

    output result("finalize")
  end
end
