defmodule Jido.AI.Reasoning.GraphOfThoughts.Actions.Advance do
  @moduledoc "Accepts one structured graph phase and routes the next phase."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/graph-of-thoughts/actions/advance",
    vsn: 1,
    name: "jido_ai_graph_of_thoughts_advance",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{state: state, turn: %{model_outcome: %{status: :error}} = turn}, _context),
    do: {:ok, complete(state, turn, :failed, :model, turn.model_outcome.reason)}

  def run(%{state: state, turn: %{model_outcome: %{status: :budget}} = turn}, _context),
    do: {:ok, complete(state, turn, :blocked, :limits, turn.model_outcome.reason)}

  def run(%{state: state, turn: %{output_allowed: false} = turn}, _context),
    do: {:ok, complete(state, turn, :blocked, :output, turn.output_reason)}

  def run(%{state: %{phase: :construct} = state, turn: turn}, _context) do
    output = turn.model_outcome.output

    nodes = Enum.map(output["nodes"], &%{id: &1["id"], content: &1["content"]})

    edges =
      Enum.map(output["edges"], fn edge ->
        %{from: edge["from"], to: edge["to"], relationship: edge["relationship"]}
      end)

    if edges_reference_nodes?(nodes, edges) do
      next =
        state
        |> Map.put(:turn, turn)
        |> Map.put(:nodes, nodes)
        |> Map.put(:edges, edges)
        |> Map.put(:phase, :synthesize)

      {:ok, %{kind: :model, input: next}}
    else
      {:ok,
       complete(
         state,
         turn,
         :blocked,
         :output,
         "graph edges must reference existing node IDs"
       )}
    end
  end

  def run(%{state: %{phase: :synthesize} = state, turn: turn}, _context) do
    answer = turn.model_outcome.output["answer"]

    reasoning = %{
      method: :graph_of_thoughts,
      nodes: state.nodes,
      edges: state.edges,
      steps_count: length(state.nodes),
      conclusion: answer
    }

    {:ok, %{kind: :complete, output: %{turn: turn, result: Result.completed(answer, reasoning)}}}
  end

  defp complete(state, turn, status, reason_code, reason) do
    nodes = Map.get(state, :nodes, [])

    reasoning = %{
      method: :graph_of_thoughts,
      nodes: nodes,
      edges: Map.get(state, :edges, []),
      steps_count: length(nodes),
      conclusion: nil
    }

    %{
      kind: :complete,
      output: %{
        turn: turn,
        result: Result.new(status, "", reason_code, reason, reasoning)
      }
    }
  end

  defp edges_reference_nodes?(nodes, edges) do
    node_ids = MapSet.new(nodes, & &1.id)

    Enum.all?(edges, fn edge ->
      MapSet.member?(node_ids, edge.from) and MapSet.member?(node_ids, edge.to)
    end)
  end
end
