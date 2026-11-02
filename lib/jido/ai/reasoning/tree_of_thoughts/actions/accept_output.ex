defmodule Jido.AI.Reasoning.TreeOfThoughts.Actions.AcceptOutput do
  @moduledoc "Moves one validated model object into Tree of Thoughts state."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/tree-of-thoughts/actions/accept-output",
    vsn: 1,
    name: "jido_ai_tree_of_thoughts_accept_output",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{state: state, turn: %{model_outcome: %{status: :error}} = turn}, _context),
    do: {:ok, terminal(state, turn, :failed, :model, turn.model_outcome.reason)}

  def run(%{state: state, turn: %{model_outcome: %{status: :budget}} = turn}, _context),
    do: {:ok, terminal(state, turn, :blocked, :limits, turn.model_outcome.reason)}

  def run(%{state: state, turn: %{output_allowed: false} = turn}, _context),
    do: {:ok, terminal(state, turn, :blocked, :output, turn.output_reason)}

  def run(%{state: %{phase: :generate} = state, turn: turn}, _context) do
    thoughts = Enum.map(turn.model_outcome.output["thoughts"], &%{content: &1["content"]})
    {:ok, %{state: %{state | turn: turn} |> Map.put(:thoughts, thoughts) |> Map.put(:phase, :evaluate)}}
  end

  def run(%{state: %{phase: :evaluate} = state, turn: turn}, _context) do
    thoughts =
      Enum.map(turn.model_outcome.output["thoughts"], fn thought ->
        %{content: thought["content"], score: thought["score"]}
      end)

    {:ok, %{state: %{state | turn: turn} |> Map.put(:thoughts, thoughts) |> Map.put(:phase, :select)}}
  end

  def run(%{state: %{phase: :synthesize} = state, turn: turn}, _context) do
    answer = turn.model_outcome.output["answer"]

    reasoning = %{
      method: :tree_of_thoughts,
      thoughts: state.thoughts,
      steps_count: length(state.thoughts),
      conclusion: answer
    }

    {:ok, %{terminal: %{turn: turn, result: Result.completed(answer, reasoning)}}}
  end

  defp terminal(state, turn, status, reason_code, reason) do
    reasoning = %{
      method: :tree_of_thoughts,
      thoughts: Map.get(state, :thoughts, []),
      steps_count: length(Map.get(state, :thoughts, [])),
      conclusion: nil
    }

    %{
      terminal: %{turn: turn, result: Result.new(status, "", reason_code, reason, reasoning)}
    }
  end
end
