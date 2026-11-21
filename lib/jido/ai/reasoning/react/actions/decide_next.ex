defmodule Jido.AI.Reasoning.ReAct.Actions.DecideNext do
  alias Jido.Joi
  @moduledoc "Routes a model outcome to completion, repair, fallback, or tools."

  alias Jido.AI.{Budget, Reasoning.Result}

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/decide-next",
    vsn: 1,
    name: "jido_ai_react_decide_next",
    description: "Choose the next graph after a model call",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{turn: turn, routes: routes}, context) when is_map(routes) do
    with {:ok, decision} <- decide(%{turn: turn}, context) do
      {:ok, route(decision, routes)}
    end
  end

  defp decide(%{turn: %{model_outcome: %{status: :budget, reason: reason}} = turn}, _context) do
    {:ok, complete(turn, Result.blocked(:limits, reason))}
  end

  defp decide(%{turn: %{model_outcome: %{status: :error}} = turn}, _context) do
    {:ok, recover_or_fail(turn, :model, turn.model_outcome.reason)}
  end

  defp decide(%{turn: %{output_allowed: false} = turn}, _context) do
    instruction = "Repair the previous response. #{turn.output_reason}. Return a valid final answer."
    {:ok, recover_or_block(turn, instruction)}
  end

  defp decide(%{turn: %{model_outcome: %{kind: :tool_calls}} = turn}, _context)
       when turn.tool_rounds >= turn.max_tool_rounds do
    {:ok, complete(turn, Result.blocked(:limits, "maximum tool rounds reached"))}
  end

  defp decide(%{turn: %{model_outcome: %{kind: :tool_calls, tool_calls: calls}} = turn}, _context)
       when turn.tool_call_count + length(calls) > turn.max_tool_calls do
    {:ok, complete(turn, Result.blocked(:limits, "maximum tool calls reached"))}
  end

  defp decide(%{turn: %{model_outcome: %{kind: :tool_calls}} = turn}, _context) do
    case Budget.resources(turn) do
      :ok ->
        kind = if review_required?(turn), do: :review, else: :tools
        {:ok, %{kind: kind, input: %{turn: turn}}}

      {:error, _budget, reason} ->
        {:ok, complete(turn, Result.blocked(:limits, reason))}
    end
  end

  defp decide(%{turn: %{model_outcome: %{kind: :final_answer}} = turn}, _context) do
    output = Map.get(turn.model_outcome, :output) || turn.model_outcome.text
    {:ok, complete(turn, Result.completed(output))}
  end

  defp recover_or_fail(turn, reason_code, reason) do
    case Budget.before_model(turn) do
      {:error, _budget, budget_reason} ->
        complete(turn, Result.blocked(:limits, budget_reason))

      :ok ->
        cond do
          turn.model_outcome.retryable and turn.model_attempt <= turn.max_retries ->
            %{kind: :model, input: %{turn: Map.update!(turn, :retries, &(&1 + 1))}}

          turn.model_outcome.retryable and turn.model_index + 1 < length(turn.models) ->
            next = %{
              turn
              | model_index: turn.model_index + 1,
                model_attempt: 0,
                retries: turn.retries + 1
            }

            %{kind: :model, input: %{turn: next}}

          true ->
            complete(turn, Result.failed(reason_code, reason))
        end
    end
  end

  defp recover_or_block(turn, instruction) do
    case Budget.before_model(turn) do
      {:error, _budget, budget_reason} ->
        complete(turn, Result.blocked(:limits, budget_reason))

      :ok ->
        cond do
          turn.model_attempt <= turn.max_retries ->
            next = %{turn | repair_instruction: instruction, retries: turn.retries + 1}
            %{kind: :model, input: %{turn: next}}

          turn.model_index + 1 < length(turn.models) ->
            next = %{
              turn
              | model_index: turn.model_index + 1,
                model_attempt: 0,
                repair_instruction: instruction,
                retries: turn.retries + 1
            }

            %{kind: :model, input: %{turn: next}}

          true ->
            complete(turn, Result.blocked(:output, turn.output_reason))
        end
    end
  end

  defp review_required?(turn) do
    review = Map.get(turn, :review_tools, [])
    Enum.any?(turn.model_outcome.tool_calls, &(&1.name in review))
  end

  defp route(%{kind: kind, input: input} = decision, routes)
       when kind in [:model, :review, :tools] do
    decision
    |> Map.put(:input, Map.put(input, :routes, routes))
    |> Map.put(:target, Map.fetch!(routes, kind))
  end

  defp route(decision, _routes), do: decision

  defp complete(turn, result), do: %{kind: :complete, output: %{turn: turn, result: result}}
end
