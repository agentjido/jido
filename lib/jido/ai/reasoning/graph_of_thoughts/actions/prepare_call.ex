defmodule Jido.AI.Reasoning.GraphOfThoughts.Actions.PrepareCall do
  @moduledoc "Prepares graph construction or graph synthesis."

  @graph_schema %{
    "type" => "object",
    "properties" => %{
      "nodes" => %{
        "type" => "array",
        "minItems" => 1,
        "items" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string", "minLength" => 1},
            "content" => %{"type" => "string", "minLength" => 1}
          },
          "required" => ["id", "content"],
          "additionalProperties" => false
        }
      },
      "edges" => %{
        "type" => "array",
        "minItems" => 1,
        "items" => %{
          "type" => "object",
          "properties" => %{
            "from" => %{"type" => "string", "minLength" => 1},
            "to" => %{"type" => "string", "minLength" => 1},
            "relationship" => %{"type" => "string", "minLength" => 1}
          },
          "required" => ["from", "to", "relationship"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["nodes", "edges"],
    "additionalProperties" => false
  }

  @answer_schema %{
    "type" => "object",
    "properties" => %{"answer" => %{"type" => "string", "minLength" => 1}},
    "required" => ["answer"],
    "additionalProperties" => false
  }

  use Jido.Action,
    id: "jido.ai/reasoning/graph-of-thoughts/actions/prepare-call",
    vsn: 1,
    name: "jido_ai_graph_of_thoughts_prepare_call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{state: %{turn: turn} = state}, _context) do
    state = Map.put_new(state, :phase, :construct)
    {instruction, output_schema} = request(state)

    turn =
      turn
      |> Map.put(:repair_instruction, instruction)
      |> Map.put(:output_schema, output_schema)

    {:ok,
     %{
       state: Map.put(state, :turn, turn),
       persist_message: state.phase == :synthesize
     }}
  end

  defp request(%{phase: :construct}) do
    {"Build a small graph of useful thoughts and explicit relationships for the user's task.", @graph_schema}
  end

  defp request(%{phase: :synthesize, nodes: nodes, edges: edges}) do
    graph = Jason.encode!(%{nodes: nodes, edges: edges})
    {"Synthesize one final answer from this thought graph: " <> graph, @answer_schema}
  end
end
