defmodule Jido.Examples.RAG.Agentic.LookupPolicy do
  alias Jido.Joi

  use Jido.Action,
    name: "rag_lookup_policy",
    description: "Retrieve policy evidence for one query.",
    schema: Joi.object(%{query: Joi.string() |> Joi.min(1)}),
    output_schema:
      Joi.object(%{
        source_id: Joi.string(),
        revision: Joi.integer(),
        text: Joi.string()
      })

  @impl true
  def run(%{query: query}, _context) do
    {:ok,
     %{
       source_id: "doc-1",
       revision: 3,
       text: "The policy limit is 30 days.",
       query: query
     }}
  end
end

defmodule Jido.Examples.RAG.Agentic.Agent do
  use Jido.AI.Agent, name: "example_agentic_rag"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:rag-agent"
      instructions "Use the retrieval tool and cite its source ID."

      limits do
        model_calls 2
        tool_rounds 1
        tool_calls 1
      end
    end

    tools do
      action Jido.Examples.RAG.Agentic.LookupPolicy
    end
  end
end
