defmodule Jido.Examples.RAG.TwoStep.Retrieve do
  use Jido.Action, name: "example_rag_retrieve"

  @impl true
  def run(%{query: query, documents: documents, top_k: top_k}, context) do
    query_terms = terms(query)

    candidates =
      documents
      |> Enum.map(fn document ->
        overlap = MapSet.intersection(query_terms, terms(document.text)) |> MapSet.size()
        Map.put(document, :retrieval_score, overlap)
      end)
      |> Enum.filter(&(&1.retrieval_score > 0))
      |> Enum.sort_by(&{-&1.retrieval_score, &1.id})
      |> Enum.take(top_k)

    client = Jido.AI.InferenceClient.Selection.client!(context)

    with {:ok, reranked} <-
           client.rerank("offline:rerank", query: query, documents: candidates) do
      results =
        reranked
        |> Enum.map(fn %{document: document, score: score} ->
          Map.put(document, :rerank_score, score)
        end)
        |> Enum.sort_by(&{-&1.rerank_score, &1.id})

      {:ok, %{query: query, results: results}}
    end
  end

  defp terms(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> MapSet.new()
  end
end

defmodule Jido.Examples.RAG.TwoStep.Generate do
  use Jido.Action, name: "example_rag_generate"

  @impl true
  def run(%{retrieval: %{results: []}}, _context) do
    {:error,
     Jido.Error.validation_error("retrieval quality gate rejected an empty result", %{
       boundary: :retrieval_quality
     })}
  end

  def run(%{retrieval: retrieval}, context) do
    client = Jido.AI.InferenceClient.Selection.client!(context)
    sources = Enum.map(retrieval.results, &%{id: &1.id, revision: &1.revision, text: &1.text})

    prompt =
      ReqLLM.Context.new([
        ReqLLM.Context.user("Question: #{retrieval.query}\nSources: #{inspect(sources)}")
      ])

    case client.generate_text("offline:rag", prompt, []) do
      {:ok, response} ->
        {:ok,
         %{
           answer: ReqLLM.Response.text(response),
           citations: Enum.map(sources, &Map.take(&1, [:id, :revision])),
           retrieved: retrieval.results,
           model: response.model
         }}

      {:error, reason} ->
        {:error, Jido.Error.execution_error("RAG generation failed", %{reason: reason})}
    end
  end
end

defmodule Jido.Examples.RAG.TwoStep.CheckAnswer do
  use Jido.Action, name: "example_rag_check_answer"

  @impl true
  def run(%{generated: generated}, _context) do
    cited? = Enum.any?(generated.citations, &String.contains?(generated.answer, "[#{&1.id}]"))

    if cited? do
      {:ok, Map.put(generated, :quality, %{citation_present: true, passed: true})}
    else
      {:error,
       Jido.Error.validation_error("answer quality gate requires a known citation", %{
         boundary: :answer_quality
       })}
    end
  end
end

defmodule Jido.Examples.RAG.TwoStep do
  use Jido.Flow,
    name: "example_two_step_rag",
    schema:
      Jido.Joi.object(%{
        query: Jido.Joi.string() |> Jido.Joi.min(1),
        documents: Jido.Joi.list(Jido.Joi.map()),
        top_k: Jido.Joi.integer() |> Jido.Joi.min(1)
      })

  alias Jido.Examples.RAG.TwoStep.{CheckAnswer, Generate, Retrieve}

  flow do
    step "retrieve",
      action: Retrieve,
      params: %{query: input(:query), documents: input(:documents), top_k: input(:top_k)}

    step "generate", action: Generate, params: %{retrieval: result("retrieve")}
    step "quality", action: CheckAnswer, params: %{generated: result("generate")}
    output result("quality")
  end
end
