defmodule Jido.AI.Reasoning.ReAct.Actions.Advance do
  alias Jido.AI.Reasoning.Actions.{
    CallModel,
    GuardOutput,
    ProjectConversation,
    RecordModelAttempt
  }

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Actions.{DecideNext, DetectToolCycle}
  alias Jido.AI.Reasoning.ReAct.ToolRound
  alias Jido.Joi

  @moduledoc "Runs one transition of the fixed ReAct loop."

  @routes %{
    model: ReAct.AfterReview,
    review: ReAct.ToolReview,
    tools: ReAct.AfterReview
  }

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/advance",
    vsn: 1,
    name: "jido_ai_react_advance",
    description: "Advance the fixed ReAct loop by one model transition",
    schema: Joi.object(%{state: Joi.map()}),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{state: %{done: false, turn: turn}}, context) do
    with {:ok, %{turn: projected_turn, context: model_context}, first} <-
           call(ProjectConversation, %{turn: turn}, context),
         {:ok, %{turn: called_turn, context: completed_context, outcome: outcome}, second} <-
           call(CallModel, %{turn: projected_turn, context: model_context}, context),
         {:ok, guard, third} <-
           call(GuardOutput, %{turn: called_turn, outcome: outcome}, context),
         {:ok, %{turn: recorded_turn}, fourth} <-
           call(
             RecordModelAttempt,
             %{
               turn: called_turn,
               outcome: outcome,
               context: completed_context,
               output_allowed: guard.allowed,
               output_reason: guard.reason
             },
             context
           ),
         {:ok, %{turn: checked_turn}, fifth} <-
           call(DetectToolCycle, %{turn: recorded_turn}, context),
         {:ok, decision, sixth} <-
           call(DecideNext, %{turn: checked_turn, routes: @routes}, context) do
      effects = first ++ second ++ third ++ fourth ++ fifth ++ sixth
      transition(decision, context, effects)
    end
  end

  def run(%{state: %{done: true} = state}, _context), do: {:ok, state}

  defp transition(%{kind: :complete, output: outcome} = decision, _context, effects) do
    result(%{decision: decision, done: true, turn: outcome.turn}, effects)
  end

  defp transition(%{kind: :model, input: %{turn: turn}}, _context, effects) do
    result(%{decision: nil, done: false, turn: turn}, effects)
  end

  defp transition(%{kind: :tools, input: %{turn: turn}}, context, effects) do
    with {:ok, next_turn, tool_effects} <- ToolRound.run(turn, context) do
      result(%{decision: nil, done: false, turn: next_turn}, effects ++ tool_effects)
    end
  end

  defp transition(%{kind: :review, input: %{turn: turn}} = decision, _context, effects) do
    result(%{decision: decision, done: true, turn: turn}, effects)
  end

  defp call(action, params, context) do
    case Jido.Exec.call_action(action, params, context) do
      {:ok, output} -> {:ok, output, []}
      {:ok, output, effects} -> {:ok, output, effects}
      {:error, _error} = error -> error
    end
  end

  defp result(state, []), do: {:ok, state}
  defp result(state, effects), do: {:ok, state, effects}
end
