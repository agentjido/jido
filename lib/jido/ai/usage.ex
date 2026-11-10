defmodule Jido.AI.Usage do
  @moduledoc "Aggregates normalized usage across all model calls in one request."

  @counter_keys [
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :compute_units,
    :input_cost,
    :output_cost,
    :total_cost
  ]

  @cost_keys [:input_cost, :output_cost, :reasoning_cost, :total_cost]

  @doc "Returns a normalized zero usage value."
  @spec zero() :: map()
  def zero, do: normalize(nil) |> Map.put(:input_includes_cached, nil)

  @doc "Normalizes provider usage and preserves reported numeric cost facts."
  @spec normalize(map() | term()) :: map()
  def normalize(usage) do
    normalized = ReqLLM.Usage.normalize(usage)

    Enum.reduce(@cost_keys, normalized, fn key, acc ->
      case field(usage, key) do
        value when is_number(value) -> Map.put(acc, key, value)
        _other -> acc
      end
    end)
  end

  @doc "Adds one provider usage value to request totals."
  @spec add(map(), map()) :: map()
  def add(total, usage) when is_map(total) and is_map(usage) do
    normalized = normalize(usage)

    totals =
      Enum.reduce(@counter_keys, total, fn key, acc ->
        Map.put(acc, key, number(acc[key]) + number(normalized[key]))
      end)

    totals
    |> Map.put(:input, totals.input_tokens)
    |> Map.put(:output, totals.output_tokens)
    |> Map.put(:cached_tokens, totals.cache_read_tokens)
    |> Map.put(:cache_creation_tokens, totals.cache_write_tokens)
    |> Map.put(
      :cache_write_tokens_by_ttl,
      add_groups(total[:cache_write_tokens_by_ttl], normalized[:cache_write_tokens_by_ttl])
    )
    |> Map.put(
      :input_includes_cached,
      combine_cache_semantics(total[:input_includes_cached], cache_semantics(normalized))
    )
  end

  @doc "Returns provider-reported prompt-cache use for one model call."
  @spec cache_observation(map(), map(), integer()) :: map()
  def cache_observation(config, usage, observed_at_ms)
      when is_map(config) and is_map(usage) and is_integer(observed_at_ms) do
    normalized = normalize(usage)
    requested_ttl = field(config, :ttl)

    %{
      requested: field(config, :enabled) == true,
      requested_ttl: requested_ttl,
      observed_at_ms: observed_at_ms,
      read_tokens: number(normalized[:cache_read_tokens]),
      write_tokens: number(normalized[:cache_write_tokens]),
      write_tokens_by_ttl: group(normalized[:cache_write_tokens_by_ttl]),
      writes: cache_writes(normalized, requested_ttl, observed_at_ms)
    }
  end

  defp add_groups(left, right) do
    Map.merge(group(left), group(right), fn _ttl, first, second ->
      number(first) + number(second)
    end)
  end

  defp cache_writes(usage, requested_ttl, observed_at_ms) do
    groups = group(usage[:cache_write_tokens_by_ttl])

    groups =
      if groups == %{} and number(usage[:cache_write_tokens]) > 0 and requested_ttl do
        %{requested_ttl => usage[:cache_write_tokens]}
      else
        groups
      end

    groups
    |> Enum.filter(fn {_ttl, tokens} -> number(tokens) > 0 end)
    |> Enum.sort_by(fn {ttl, _tokens} -> to_string(ttl) end)
    |> Enum.map(fn {ttl, tokens} ->
      ttl_ms = ttl_ms(ttl)

      %{
        ttl: ttl,
        ttl_ms: ttl_ms,
        token_count: tokens,
        observed_at_ms: observed_at_ms,
        estimated_expires_at_ms: expires_at(observed_at_ms, ttl_ms)
      }
    end)
  end

  defp group(value) when is_map(value), do: value
  defp group(_value), do: %{}
  defp number(value) when is_number(value), do: value
  defp number(_value), do: 0
  defp expires_at(_observed_at_ms, nil), do: nil
  defp expires_at(observed_at_ms, ttl_ms), do: observed_at_ms + ttl_ms

  defp ttl_ms(value) when is_integer(value) and value >= 0, do: value

  defp ttl_ms(value) when is_binary(value) do
    case Regex.run(~r/^(\d+)(ms|s|m|h)$/, value) do
      [_, count, unit] -> String.to_integer(count) * unit_ms(unit)
      _other -> nil
    end
  end

  defp ttl_ms(_value), do: nil
  defp unit_ms("ms"), do: 1
  defp unit_ms("s"), do: 1_000
  defp unit_ms("m"), do: 60_000
  defp unit_ms("h"), do: 3_600_000

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil

  defp cache_semantics(usage) do
    if Enum.any?(@counter_keys, &(number(usage[&1]) > 0)),
      do: usage[:input_includes_cached],
      else: nil
  end

  defp combine_cache_semantics(value, nil), do: value
  defp combine_cache_semantics(nil, value), do: value
  defp combine_cache_semantics(value, value), do: value
  defp combine_cache_semantics(_left, _right), do: :mixed
end
