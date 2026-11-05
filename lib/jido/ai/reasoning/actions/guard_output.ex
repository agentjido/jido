defmodule Jido.AI.Reasoning.Actions.GuardOutput do
  alias Jido.Joi
  @moduledoc "Applies final-answer guards to one model outcome."

  alias Jido.AI.Toolset
  alias Jido.Telemetry.AI, as: Telemetry

  @default_max_output_chars 32_000
  @max_tool_calls_per_response 4

  use Jido.Action,
    id: "jido.ai/reasoning/actions/guard-output",
    vsn: 1,
    name: "jido_ai_guard_output",
    description: "Apply the Agent output guard",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{outcome: %{status: :error}}, _context),
    do: {:ok, %{allowed: false, reason: "model request failed"}}

  def run(%{outcome: %{status: :budget, reason: reason}}, _context),
    do: {:ok, %{allowed: false, reason: reason}}

  def run(%{turn: turn, outcome: %{kind: :tool_calls} = outcome}, context) do
    observe_token_limit(turn, outcome, context)

    reason =
      finish_reason(outcome.finish_reason) ||
        tool_call_reason(outcome.tool_calls, turn, outcome, context)

    {:ok, decision(reason)}
  end

  def run(%{turn: turn, outcome: %{kind: :final_answer, text: text} = outcome}, context) do
    observe_token_limit(turn, outcome, context)

    output = Map.get(outcome, :output)
    content = output_content(text, output)
    max_chars = Map.get(turn, :max_output_chars, @default_max_output_chars)

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

          String.length(content) > max_chars ->
            observe_limit(:output_chars, String.length(content), max_chars, turn, outcome, context)
            "model output is longer than #{max_chars} characters"

          true ->
            nil
        end

    {:ok, decision(reason)}
  end

  defp tool_call_reason([], _turn, _outcome, _context),
    do: "model requested a tool round without tool calls"

  defp tool_call_reason(calls, turn, outcome, context) do
    ids = Enum.map(calls, & &1.id)

    cond do
      length(calls) > @max_tool_calls_per_response ->
        observe_limit(
          :tool_calls_per_response,
          length(calls),
          @max_tool_calls_per_response,
          turn,
          outcome,
          context
        )

        "one model response can contain at most #{@max_tool_calls_per_response} tool calls"

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

  defp observe_token_limit(turn, %{finish_reason: :length} = outcome, context),
    do: Telemetry.limit_exceeded(context, :token_limit, %{}, limit_metadata(turn, outcome))

  defp observe_token_limit(_turn, _outcome, _context), do: :ok

  defp observe_limit(limit, value, maximum, turn, outcome, context) do
    Telemetry.limit_exceeded(
      context,
      limit,
      %{value: value, maximum: maximum},
      limit_metadata(turn, outcome)
    )
  end

  defp limit_metadata(turn, outcome) do
    %{
      request_id: Map.get(turn, :request_id),
      run_id: Map.get(turn, :run_id),
      model: Map.get(outcome, :model)
    }
  end

  defp finish_reason(reason) when reason in [nil, :stop, :tool_calls], do: nil
  defp finish_reason(:length), do: "model output stopped at its token limit"
  defp finish_reason(:content_filter), do: "model output was stopped by a content filter"
  defp finish_reason(:cancelled), do: "model output was cancelled"
  defp finish_reason(:incomplete), do: "model output was incomplete"
  defp finish_reason(:error), do: "model returned an error finish reason"
  defp finish_reason(_reason), do: "model returned an unknown finish reason"

  defp output_content(text, nil), do: text
  defp output_content(_text, output), do: JSON.encode!(output)

  defp decision(nil), do: %{allowed: true, reason: ""}
  defp decision(reason), do: %{allowed: false, reason: reason}
end
