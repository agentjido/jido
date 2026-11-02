defmodule Jido.AI.Budget do
  @moduledoc "Checks portable request budgets before Jido AI starts more work."

  @type check_result :: :ok | {:error, atom(), String.t()}

  @doc "Checks all budgets before a model call starts."
  @spec before_model(map(), integer()) :: check_result()
  def before_model(turn, now \\ System.system_time(:millisecond))

  def before_model(turn, now) when is_map(turn) and is_integer(now) do
    with :ok <- limit(turn.model_calls, field(turn, :max_model_calls), :model_calls),
         do: resources(turn, now)
  end

  @doc "Checks time, token, and cost budgets before another graph phase starts."
  @spec resources(map(), integer()) :: check_result()
  def resources(turn, now \\ System.system_time(:millisecond))

  def resources(turn, now) when is_map(turn) and is_integer(now) do
    usage = field(turn, :usage) || %{}

    with :ok <- elapsed(turn, now),
         :ok <- limit(number(field(usage, :input_tokens)), field(turn, :max_input_tokens), :input_tokens),
         :ok <- limit(number(field(usage, :output_tokens)), field(turn, :max_output_tokens), :output_tokens),
         :ok <- limit(number(field(usage, :total_tokens)), field(turn, :max_total_tokens), :total_tokens),
         do: limit(number(field(usage, :total_cost)), field(turn, :max_total_cost), :total_cost)
  end

  @doc "Returns the remaining request time in milliseconds."
  @spec remaining_elapsed_ms(map(), integer()) :: pos_integer() | nil
  def remaining_elapsed_ms(turn, now \\ System.system_time(:millisecond))

  def remaining_elapsed_ms(turn, now) when is_map(turn) and is_integer(now) do
    case {field(turn, :started_at_ms), field(turn, :max_elapsed_ms)} do
      {started_at, limit}
      when is_integer(started_at) and is_integer(limit) and limit > 0 ->
        max(limit - max(now - started_at, 0), 1)

      _other ->
        nil
    end
  end

  @doc "Returns a portable summary of used and configured budgets."
  @spec summary(map(), integer()) :: map()
  def summary(turn, now \\ System.system_time(:millisecond))

  def summary(turn, now) when is_map(turn) and is_integer(now) do
    started_at = field(turn, :started_at_ms)

    %{
      elapsed_ms: if(is_integer(started_at), do: max(now - started_at, 0), else: nil),
      limits: %{
        elapsed_ms: field(turn, :max_elapsed_ms),
        model_calls: field(turn, :max_model_calls),
        tool_rounds: field(turn, :max_tool_rounds),
        tool_calls: field(turn, :max_tool_calls),
        input_tokens: field(turn, :max_input_tokens),
        output_tokens: field(turn, :max_output_tokens),
        total_tokens: field(turn, :max_total_tokens),
        total_cost: field(turn, :max_total_cost)
      }
    }
  end

  defp elapsed(turn, now) do
    case {field(turn, :started_at_ms), field(turn, :max_elapsed_ms)} do
      {started_at, limit}
      when is_integer(started_at) and is_integer(limit) and limit > 0 and
             now - started_at >= limit ->
        exceeded(:elapsed_ms)

      _other ->
        :ok
    end
  end

  defp limit(_used, nil, _kind), do: :ok

  defp limit(used, limit, kind) when is_number(limit) and limit >= 0 and used >= limit,
    do: exceeded(kind)

  defp limit(_used, _limit, _kind), do: :ok

  defp exceeded(:elapsed_ms), do: {:error, :elapsed_ms, "maximum elapsed time reached"}
  defp exceeded(:model_calls), do: {:error, :model_calls, "maximum model calls reached"}
  defp exceeded(:input_tokens), do: {:error, :input_tokens, "maximum input tokens reached"}
  defp exceeded(:output_tokens), do: {:error, :output_tokens, "maximum output tokens reached"}
  defp exceeded(:total_tokens), do: {:error, :total_tokens, "maximum total tokens reached"}
  defp exceeded(:total_cost), do: {:error, :total_cost, "maximum total cost reached"}

  defp number(value) when is_number(value), do: value
  defp number(_value), do: 0
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
