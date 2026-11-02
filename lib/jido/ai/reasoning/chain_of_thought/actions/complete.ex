defmodule Jido.AI.Reasoning.ChainOfThought.Actions.Complete do
  @moduledoc "Builds the terminal result from one validated Chain of Thought object."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/chain-of-thought/actions/complete",
    vsn: 1,
    name: "jido_ai_chain_of_thought_complete",
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
        %{turn: %{model_outcome: %{output: %{"steps" => steps, "conclusion" => conclusion}}} = turn},
        _context
      ) do
    reasoning = %{
      method: :chain_of_thought,
      steps: Enum.map(steps, &%{number: &1["number"], content: &1["content"]}),
      steps_count: length(steps),
      conclusion: conclusion
    }

    {:ok, %{turn: turn, result: Result.completed(conclusion, reasoning)}}
  end

  def run(%{turn: turn}, _context),
    do: {:ok, terminal(turn, :blocked, :output, "model output is missing required structured data")}

  defp terminal(turn, status, reason_code, reason) do
    reasoning = %{method: :chain_of_thought, steps: [], steps_count: 0, conclusion: nil}
    %{turn: turn, result: Result.new(status, "", reason_code, reason, reasoning)}
  end
end
