defmodule Jido.Flow.CallPolicy do
  @moduledoc """
  Defines bounded timeout and retry data for an Action call.

  A policy is immutable Flow data. `Jido.Exec` applies it during execution.
  Child Flow calls do not accept an Action attempt policy.
  """

  alias Jido.Flow.Error

  require Jido.Authoring.Limits

  @maximum_attempts 10_000
  @maximum_duration_ms Jido.Authoring.Limits.maximum_duration_ms()
  @backoffs [:none, :fixed, :exponential]

  @type retry :: %{
          required(:max_attempts) => pos_integer(),
          required(:backoff) => :none | :fixed | :exponential,
          required(:base_delay_ms) => non_neg_integer(),
          required(:max_delay_ms) => non_neg_integer()
        }
  @type t :: %{
          optional(:timeout_ms) => pos_integer(),
          optional(:retry) => retry()
        }

  @doc false
  @spec from_options(term(), term(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def from_options(nil, timeout_ms, retry) do
    %{}
    |> maybe_put(:timeout_ms, timeout_ms)
    |> maybe_put(:retry, retry)
    |> normalize()
  end

  def from_options(policy, nil, nil), do: normalize(policy)

  def from_options(policy, timeout_ms, retry) do
    invalid(
      %{policy: policy, timeout_ms: timeout_ms, retry: retry},
      :mixed_policy_fields
    )
  end

  @doc false
  @spec from_options(term(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def from_options(timeout_ms, retry), do: from_options(nil, timeout_ms, retry)

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(policy) when is_list(policy) do
    if Keyword.keyword?(policy), do: policy |> Map.new() |> normalize(), else: invalid(policy)
  end

  def normalize(%{} = policy) when not is_struct(policy) do
    with {:ok, policy} <- normalize_keys(policy, [:timeout_ms, :retry]),
         {:ok, timeout} <- timeout(Map.get(policy, :timeout_ms)),
         {:ok, retry} <- normalize_retry(Map.get(policy, :retry)) do
      {:ok, %{} |> maybe_put(:timeout_ms, timeout) |> maybe_put(:retry, retry)}
    end
  end

  def normalize(policy), do: invalid(policy)

  @doc false
  @spec timeout_ms(t()) :: pos_integer() | nil
  def timeout_ms(policy), do: Map.get(policy, :timeout_ms)

  @doc false
  @spec retry(t()) :: retry() | nil
  def retry(policy), do: Map.get(policy, :retry)

  defp timeout(nil), do: {:ok, nil}

  defp timeout(value) when is_integer(value) and value > 0 and value <= @maximum_duration_ms,
    do: {:ok, value}

  defp timeout(value), do: invalid(value, :timeout_ms)

  defp normalize_retry(nil), do: {:ok, nil}

  defp normalize_retry(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: value |> Map.new() |> normalize_retry(),
      else: invalid(value, :retry)
  end

  defp normalize_retry(%{} = value) when not is_struct(value) do
    allowed = [:max_attempts, :delay_ms, :backoff, :base_delay_ms, :max_delay_ms]

    with {:ok, value} <- normalize_keys(value, allowed),
         max_attempts when is_integer(max_attempts) and max_attempts in 1..@maximum_attempts <-
           Map.get(value, :max_attempts),
         {:ok, backoff} <- normalize_backoff(value) do
      {:ok, Map.put(backoff, :max_attempts, max_attempts)}
    else
      {:error, error} -> {:error, error}
      _invalid -> invalid(value, :retry)
    end
  end

  defp normalize_retry(value), do: invalid(value, :retry)

  defp normalize_keys(value, allowed) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {key, item}, {:ok, normalized} ->
      normalized_key =
        if is_binary(key), do: Enum.find(allowed, &(Atom.to_string(&1) == key)), else: key

      cond do
        normalized_key not in allowed ->
          {:halt, invalid(value, {:unknown_field, key})}

        Map.has_key?(normalized, normalized_key) ->
          {:halt, invalid(value, {:duplicate_field, normalized_key})}

        true ->
          {:cont, {:ok, Map.put(normalized, normalized_key, item)}}
      end
    end)
  end

  defp normalize_backoff(%{delay_ms: delay} = retry) do
    if Map.has_key?(retry, :backoff) or Map.has_key?(retry, :base_delay_ms) or
         Map.has_key?(retry, :max_delay_ms) do
      invalid(retry, :mixed_retry_delay_fields)
    else
      fixed_backoff(delay, retry)
    end
  end

  defp normalize_backoff(retry) do
    backoff = normalize_backoff_name(Map.get(retry, :backoff, :none))
    base = Map.get(retry, :base_delay_ms, 0)
    maximum = Map.get(retry, :max_delay_ms, backoff_maximum(backoff, base))

    case backoff do
      :none when base == 0 and maximum == 0 ->
        {:ok, %{backoff: :none, base_delay_ms: 0, max_delay_ms: 0}}

      :fixed ->
        fixed_backoff(base, retry, maximum)

      :exponential
      when is_integer(base) and base > 0 and base <= @maximum_duration_ms and
             is_integer(maximum) and maximum >= base and maximum <= @maximum_duration_ms ->
        {:ok, %{backoff: :exponential, base_delay_ms: base, max_delay_ms: maximum}}

      _invalid ->
        invalid(retry, :retry_backoff)
    end
  end

  defp normalize_backoff_name(value) when value in @backoffs, do: value
  defp normalize_backoff_name("none"), do: :none
  defp normalize_backoff_name("fixed"), do: :fixed
  defp normalize_backoff_name("exponential"), do: :exponential
  defp normalize_backoff_name(value), do: value

  defp backoff_maximum(:fixed, base), do: base
  defp backoff_maximum(_backoff, _base), do: 0

  defp fixed_backoff(delay, retry, maximum \\ nil)

  defp fixed_backoff(delay, _retry, nil)
       when is_integer(delay) and delay >= 0 and delay <= @maximum_duration_ms do
    {:ok, fixed_backoff_value(delay)}
  end

  defp fixed_backoff(delay, _retry, delay)
       when is_integer(delay) and delay >= 0 and delay <= @maximum_duration_ms do
    {:ok, fixed_backoff_value(delay)}
  end

  defp fixed_backoff(_delay, retry, _maximum), do: invalid(retry, :retry_backoff)

  defp fixed_backoff_value(0),
    do: %{backoff: :none, base_delay_ms: 0, max_delay_ms: 0}

  defp fixed_backoff_value(delay),
    do: %{backoff: :fixed, base_delay_ms: delay, max_delay_ms: delay}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp invalid(value, field \\ :policy) do
    {:error,
     Error.validation_error("Flow call policy is invalid", %{
       reason: :invalid_call_policy,
       field: field,
       value: value
     })}
  end
end
