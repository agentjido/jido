defmodule Jido.AI.Reasoning.Actions.GuardInput do
  @moduledoc "Checks one request before its reasoning graph starts."

  @blocked_fragments ["ignore previous instructions", "reveal your system prompt"]

  use Jido.Action,
    id: "jido.ai/reasoning/actions/guard-input",
    vsn: 1,
    name: "jido_ai_guard_input",
    description: "Check one request before model work starts",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, context) do
    cond do
      reason = rejection_reason(turn.input) ->
        {:ok, blocked(:input, reason)}

      Map.get(turn, :review_required, false) and not Jido.Exec.supports?(context, :waits) ->
        {:ok, blocked(:review, "execution host does not support waits")}

      true ->
        {:ok, %{allowed: true, reason_code: :none, reason: nil}}
    end
  end

  defp rejection_reason(input) do
    text = input_text(input)
    normalized = String.downcase(text)

    cond do
      empty_input?(input, text) ->
        "input is empty"

      reason = size_reason(input) ->
        reason

      Enum.any?(@blocked_fragments, &String.contains?(normalized, &1)) ->
        "input contains a blocked instruction pattern"

      true ->
        nil
    end
  end

  defp input_text(input) when is_binary(input), do: input

  defp input_text(input) when is_list(input) do
    Enum.map_join(input, " ", fn part ->
      case Map.get(part, :text, Map.get(part, "text")) do
        text when is_binary(text) -> text
        _other -> ""
      end
    end)
  end

  defp empty_input?(input, text) when is_binary(input), do: String.trim(text) == ""

  defp empty_input?(input, text) when is_list(input) do
    String.trim(text) == "" and
      not Enum.any?(input, fn part ->
        Enum.any?([:url, :data, :file_id], fn key ->
          value = Map.get(part, key, Map.get(part, Atom.to_string(key)))
          is_binary(value) and value != ""
        end)
      end)
  end

  defp size_reason(input) when is_binary(input) do
    if String.length(input) > 2_000,
      do: "input is longer than 2000 characters"
  end

  defp size_reason(input) when is_list(input) do
    if byte_size(:erlang.term_to_binary(input)) > 2_000_000,
      do: "input is larger than 2 MB"
  end

  defp blocked(reason_code, reason),
    do: %{allowed: false, reason_code: reason_code, reason: reason}
end
