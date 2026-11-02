defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.Actions.Complete do
  @moduledoc "Builds the terminal result from one validated Algorithm of Thoughts object."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/algorithm-of-thoughts/actions/complete",
    vsn: 1,
    name: "jido_ai_algorithm_of_thoughts_complete",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: %{model_outcome: %{status: :error}} = turn}, _context),
    do: {:ok, terminal(turn, :failed, :model, turn.model_outcome.reason)}

  def run(%{turn: %{model_outcome: %{status: :budget}} = turn}, _context),
    do: {:ok, terminal(turn, :blocked, :limits, turn.model_outcome.reason)}

  def run(%{turn: %{output_allowed: false} = turn}, _context),
    do: {:ok, terminal(turn, :blocked, :output, turn.output_reason)}

  def run(
        %{turn: %{model_outcome: %{output: %{"operations" => operations, "answer" => answer}}} = turn},
        _context
      ) do
    reasoning = %{
      method: :algorithm_of_thoughts,
      operations: operations,
      steps_count: length(operations),
      conclusion: answer
    }

    {:ok, %{turn: turn, result: Result.completed(answer, reasoning)}}
  end

  def run(%{turn: turn}, _context),
    do: {:ok, terminal(turn, :blocked, :output, "model output is missing required structured data")}

  defp terminal(turn, status, reason_code, reason) do
    reasoning = %{method: :algorithm_of_thoughts, operations: [], steps_count: 0, conclusion: nil}
    %{turn: turn, result: Result.new(status, "", reason_code, reason, reasoning)}
  end
end
