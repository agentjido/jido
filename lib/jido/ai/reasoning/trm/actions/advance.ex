defmodule Jido.AI.Reasoning.TRM.Actions.Advance do
  @moduledoc "Accepts one structured TRM phase and routes the next phase."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/trm/actions/advance",
    vsn: 1,
    name: "jido_ai_trm_advance",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{state: state, turn: %{model_outcome: %{status: :error}} = turn}, _context),
    do: {:ok, complete(state, turn, :failed, :model, turn.model_outcome.reason)}

  def run(%{state: state, turn: %{model_outcome: %{status: :budget}} = turn}, _context),
    do: {:ok, complete(state, turn, :blocked, :limits, turn.model_outcome.reason)}

  def run(%{state: state, turn: %{output_allowed: false} = turn}, _context),
    do: {:ok, complete(state, turn, :blocked, :output, turn.output_reason)}

  def run(%{state: %{phase: :draft} = state, turn: turn}, _context) do
    next =
      state |> Map.put(:turn, turn) |> Map.put(:draft, turn.model_outcome.output["draft"]) |> Map.put(:phase, :critique)

    {:ok, %{kind: :model, input: next}}
  end

  def run(%{state: %{phase: :critique} = state, turn: turn}, _context) do
    next =
      state
      |> Map.put(:turn, turn)
      |> Map.put(:critique, turn.model_outcome.output["critique"])
      |> Map.put(:phase, :revise)

    {:ok, %{kind: :model, input: next}}
  end

  def run(%{state: %{phase: :revise} = state, turn: turn}, _context) do
    answer = turn.model_outcome.output["answer"]

    reasoning = %{
      method: :trm,
      draft: state.draft,
      critique: state.critique,
      iterations: 1,
      steps_count: 3,
      conclusion: answer
    }

    {:ok, %{kind: :complete, output: %{turn: turn, result: Result.completed(answer, reasoning)}}}
  end

  defp complete(state, turn, status, reason_code, reason) do
    reasoning = %{
      method: :trm,
      draft: Map.get(state, :draft),
      critique: Map.get(state, :critique),
      iterations: 1,
      steps_count: completed_steps(state),
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

  defp completed_steps(state) do
    Enum.count([Map.get(state, :draft), Map.get(state, :critique)], &is_binary/1)
  end
end
