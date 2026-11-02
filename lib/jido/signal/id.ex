defmodule Jido.Signal.ID do
  @moduledoc """
  Generates and reads RFC 9562 UUID version 7 Signal IDs.

  A UUID7 contains a Unix millisecond timestamp followed by random data. IDs
  from different milliseconds sort by time. IDs from the same millisecond have
  random order; this module does not keep a process-local sequence counter.
  """

  @type uuid7 :: String.t()
  @type timestamp :: non_neg_integer()
  @type comparison_result :: :lt | :eq | :gt

  @max_unix_ts_ms 0xFFFFFFFFFFFF
  @uuid7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  @doc "Returns a new UUID7 and its embedded Unix millisecond timestamp."
  @spec generate() :: {uuid7(), timestamp()}
  def generate do
    timestamp = System.system_time(:millisecond)
    {uuid7(timestamp, :crypto.strong_rand_bytes(10)), timestamp}
  end

  @doc "Returns a new UUID7 string."
  @spec generate!() :: uuid7()
  def generate! do
    {uuid, _timestamp} = generate()
    uuid
  end

  @doc "Returns the Unix millisecond timestamp embedded in a valid UUID7."
  @spec extract_timestamp(uuid7()) :: timestamp()
  def extract_timestamp(uuid) when is_binary(uuid) do
    <<timestamp::48, _rest::binary>> = decode_uuid7!(uuid)
    timestamp
  end

  @doc "Compares the complete binary values of two valid UUID7 strings."
  @spec compare(uuid7(), uuid7()) :: comparison_result()
  def compare(uuid1, uuid2) when is_binary(uuid1) and is_binary(uuid2) do
    raw1 = decode_uuid7!(uuid1)
    raw2 = decode_uuid7!(uuid2)

    cond do
      raw1 < raw2 -> :lt
      raw1 > raw2 -> :gt
      true -> :eq
    end
  end

  @doc "Returns true when the value is a valid UUID7 string."
  @spec valid?(term()) :: boolean()
  def valid?(uuid), do: match?({:ok, _raw}, decode_uuid7(uuid))

  defp decode_uuid7(uuid) when is_binary(uuid) do
    with true <- Regex.match?(@uuid7_regex, uuid),
         {:ok, <<_timestamp::48, 7::4, _rand_a::12, 2::2, _rand_b::62>> = raw} <-
           decode_uuid(uuid) do
      {:ok, raw}
    else
      _error -> :error
    end
  end

  defp decode_uuid7(_value), do: :error

  defp uuid7(timestamp_ms, random_bytes)
       when is_integer(timestamp_ms) and timestamp_ms in 0..@max_unix_ts_ms and
              byte_size(random_bytes) == 10 do
    <<rand_a::12, rand_b::62, _unused::6>> = random_bytes

    <<timestamp_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  defp decode_uuid7!(uuid) do
    case decode_uuid7(uuid) do
      {:ok, raw} -> raw
      :error -> raise ArgumentError, "expected a valid UUID7 string"
    end
  end

  defp decode_uuid(uuid) do
    uuid
    |> String.replace("-", "")
    |> Base.decode16(case: :mixed)
  end

  defp format_uuid(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
           e::binary-size(12)>>
       ) do
    Enum.join([a, b, c, d, e], "-")
  end
end
