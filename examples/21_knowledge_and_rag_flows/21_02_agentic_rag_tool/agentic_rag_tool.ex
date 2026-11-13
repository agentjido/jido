defmodule Jido.Examples.RAG.Agentic.LookupPolicy do
  use Jido.Action,
    name: "rag_lookup_policy",
    description: "Retrieve policy evidence for one query.",
    schema: Jido.Joi.object(%{query: Jido.Joi.string() |> Jido.Joi.min(1)}),
    output_schema:
      Jido.Joi.object(%{
        source_id: Jido.Joi.string(),
        revision: Jido.Joi.integer(),
        text: Jido.Joi.string()
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
