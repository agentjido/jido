defmodule Jido.AI.Reasoning.ChainOfDraft.Actions.Complete do
  @moduledoc "Builds the terminal result from one validated Chain of Draft object."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/chain-of-draft/actions/complete",
    vsn: 1,
    name: "jido_ai_chain_of_draft_complete",
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
        %{turn: %{model_outcome: %{output: %{"drafts" => drafts, "answer" => answer}}} = turn},
        _context
      ) do
    reasoning = %{
      method: :chain_of_draft,
      drafts: drafts,
      steps_count: length(drafts),
      conclusion: answer
    }

    {:ok, %{turn: turn, result: Result.completed(answer, reasoning)}}
  end

  def run(%{turn: turn}, _context),
    do: {:ok, terminal(turn, :blocked, :output, "model output is missing required structured data")}

  defp terminal(turn, status, reason_code, reason) do
    reasoning = %{method: :chain_of_draft, drafts: [], steps_count: 0, conclusion: nil}
    %{turn: turn, result: Result.new(status, "", reason_code, reason, reasoning)}
  end
end
