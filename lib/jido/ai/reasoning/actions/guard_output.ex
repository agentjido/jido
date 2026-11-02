defmodule Jido.AI.Reasoning.Actions.GuardOutput do
  @moduledoc "Applies final-answer guards to one model outcome."

  alias Jido.AI.Toolset

  use Jido.Action,
    id: "jido.ai/reasoning/actions/guard-output",
    vsn: 1,
    name: "jido_ai_guard_output",
    description: "Apply the Agent output guard",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{outcome: %{status: :error}}, _context),
    do: {:ok, %{allowed: false, reason: "model request failed"}}

  def run(%{outcome: %{status: :budget, reason: reason}}, _context),
    do: {:ok, %{allowed: false, reason: reason}}

  def run(%{turn: turn, outcome: %{kind: :tool_calls} = outcome}, _context) do
    reason = finish_reason(outcome.finish_reason) || tool_call_reason(outcome.tool_calls, turn)
    {:ok, decision(reason)}
  end

  def run(%{turn: turn, outcome: %{kind: :final_answer, text: text} = outcome}, _context) do
    output = Map.get(outcome, :output)
    content = output_content(text, output)

    reason =
      finish_reason(outcome.finish_reason) ||
        cond do
          not Toolset.requirement_satisfied?(
            turn.tool_requirement,
            turn.tool_rounds,
            turn.tools
          ) ->
            "tool use is required before a final answer"

          not is_nil(Map.get(turn, :output_schema)) and is_nil(output) ->
            "model output is missing required structured data"

          String.trim(content) == "" ->
            "model output is empty"

          String.length(content) > 4_000 ->
            "model output is too long"

          true ->
            nil
        end

    {:ok, decision(reason)}
  end

  defp tool_call_reason([], _turn), do: "model requested a tool round without tool calls"

  defp tool_call_reason(calls, turn) do
    ids = Enum.map(calls, & &1.id)

    cond do
      length(calls) > 4 ->
        "one model response can contain at most 4 tool calls"

      length(ids) != length(Enum.uniq(ids)) ->
        "tool call IDs must be unique"

      Enum.any?(calls, &(&1.name not in Toolset.names(turn.tools))) ->
        "model requested a tool that is not allowed"

      true ->
        Enum.find_value(calls, fn call ->
          case Toolset.validate_call(turn.tools, call) do
            :ok -> nil
            {:error, reason} -> "invalid tool call: #{inspect(reason)}"
          end
        end)
    end
  end

  defp finish_reason(reason) when reason in [nil, :stop, :tool_calls], do: nil
  defp finish_reason(:length), do: "model output stopped at its token limit"
  defp finish_reason(:content_filter), do: "model output was stopped by a content filter"
  defp finish_reason(:cancelled), do: "model output was cancelled"
  defp finish_reason(:incomplete), do: "model output was incomplete"
  defp finish_reason(:error), do: "model returned an error finish reason"
  defp finish_reason(_reason), do: "model returned an unknown finish reason"

  defp output_content(text, nil), do: text
  defp output_content(_text, output), do: Jason.encode!(output)

  defp decision(nil), do: %{allowed: true, reason: ""}
  defp decision(reason), do: %{allowed: false, reason: reason}
end
