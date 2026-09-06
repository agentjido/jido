defmodule Jido.Examples.GroundedAnswer.Retrieve do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter
  use Jido.Action, name: "llm_retrieve_evidence"

  def evidence_schema,
    do:
      Zoi.list(
        Zoi.object(%{
          id: Zoi.string(),
          revision: Zoi.string(),
          text: Zoi.string(),
          page: Zoi.integer() |> Zoi.min(1)
        })
      )

  def run(input, %{agent_state: state} = context) do
    with {:ok, query} <- query(input, state, context),
         {:ok, local} <- Adapter.call(context, :retriever, :retrieve, %{query: query}),
         {:ok, raw} <- fallback(local, query, input.allow_web, context),
         {:ok, evidence} <- Adapter.parse(evidence_schema(), raw) do
      if evidence == [],
        do: Adapter.invalid("no evidence"),
        else: {:ok, %{prompt: input.prompt, evidence: evidence}}
    end
  end

  defp query(%{resolve: false, prompt: prompt}, _, _), do: {:ok, prompt}

  defp query(input, state, context) do
    with {:ok, raw} <-
           Adapter.call(context, :resolver, :resolve, %{
             prompt: input.prompt,
             messages: state.messages
           }),
         {:ok, parsed} <- Adapter.parse(Zoi.object(%{query: Zoi.string() |> Zoi.min(1)}), raw),
         do: {:ok, parsed.query}
  end

  defp fallback([], query, true, context),
    do: Adapter.call(context, :web, :search, %{query: query})

  defp fallback(evidence, _, _, _), do: {:ok, evidence}
end

defmodule Jido.Examples.GroundedAnswer.Commit do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter
  use Jido.Action, name: "llm_grounded_commit"

  def run(input, %{agent_state: state}) do
    schema =
      Zoi.object(%{
        answer: Zoi.string() |> Zoi.min(1),
        citations:
          Zoi.list(Zoi.object(%{id: Zoi.string(), revision: Zoi.string(), page: Zoi.integer()}))
          |> Zoi.min(1)
      })

    with {:ok, result} <- Adapter.parse(schema, input.output) do
      valid =
        Enum.all?(result.citations, fn cite ->
          Enum.any?(input.evidence, &(Map.take(&1, [:id, :revision, :page]) == cite))
        end)

      if valid do
        {:ok,
         %{
           answer: result.answer,
           citations: result.citations,
           messages:
             state.messages ++
               [
                 %{role: :user, content: input.prompt},
                 %{role: :assistant, content: result.answer}
               ]
         }}
      else
        Adapter.invalid("citation is not in the supplied evidence revision")
      end
    end
  end
end

defmodule Jido.Examples.GroundedAnswer.Pipeline do
  @moduledoc "Retrieval and generation effects precede terminal provenance validation."
  alias Jido.Examples.LLM.Adapter

  use Jido.Flow,
    name: "llm_grounded_flow",
    schema:
      Zoi.object(%{
        prompt: Zoi.string() |> Zoi.min(1),
        resolve: Zoi.boolean() |> Zoi.default(false),
        allow_web: Zoi.boolean() |> Zoi.default(false)
      })

  flow do
    step "retrieve",
      action: Jido.Examples.GroundedAnswer.Retrieve,
      params: %{prompt: input(:prompt), resolve: input(:resolve), allow_web: input(:allow_web)}

    step "generate" do
      action input <- result("retrieve"), context: context do
        with {:ok, answer} <- Adapter.call(context, :model, :complete, input),
             do: {:ok, Map.put(input, :output, answer)}
      end
    end

    step "commit", action: Jido.Examples.GroundedAnswer.Commit, params: result("generate")
    output result("commit")
  end
end

defmodule Jido.Examples.GroundedAnswer do
  @moduledoc "Evidence identity, revision, and page checks; this does not establish factual accuracy."

  use Jido.Agent, name: "llm_grounded_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             citations: Zoi.list(Zoi.map()) |> Zoi.default([]),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm"

    route "llm.grounded", Jido.Examples.GroundedAnswer.Pipeline do
      define :answer, args: [:prompt]
    end
  end
end
