defmodule Jido.Id do
  @moduledoc """
  Creates the RFC 9562 UUID formats used by Jido.

  A UUIDv7 contains a Unix millisecond timestamp followed by random data.
  Values from different milliseconds sort by time. Values from the same
  millisecond have random order. This module does not keep a process-local
  sequence counter.

  `uuid8/1` formats caller-owned deterministic bytes as a UUIDv8. The caller
  remains responsible for the meaning and stability of those bytes.
  """

  import Bitwise

  @type uuid7 :: String.t()
  @type uuid8 :: String.t()
  @type timestamp :: non_neg_integer()
  @type comparison_result :: :lt | :eq | :gt

  @max_unix_ts_ms 0xFFFFFFFFFFFF
  @uuid7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  @doc "Returns a new UUIDv7 identifier."
  @spec uuid7() :: uuid7()
  def uuid7 do
    uuid7(System.system_time(:millisecond), :crypto.strong_rand_bytes(10))
  end

  @doc "Returns true when the value is a valid UUIDv7 identifier."
  @spec uuid7?(term()) :: boolean()
  def uuid7?(uuid), do: match?({:ok, _raw}, decode_uuid7(uuid))

  @doc "Returns the Unix millisecond timestamp in a valid UUIDv7 identifier."
  @spec uuid7_timestamp(uuid7()) :: timestamp()
  def uuid7_timestamp(uuid) when is_binary(uuid) do
    <<timestamp::48, _rest::binary>> = decode_uuid7!(uuid)
    timestamp
  end

  @doc "Compares the complete binary values of two valid UUIDv7 identifiers."
  @spec compare_uuid7(uuid7(), uuid7()) :: comparison_result()
  def compare_uuid7(uuid1, uuid2) when is_binary(uuid1) and is_binary(uuid2) do
    raw1 = decode_uuid7!(uuid1)
    raw2 = decode_uuid7!(uuid2)

    cond do
      raw1 < raw2 -> :lt
      raw1 > raw2 -> :gt
      true -> :eq
    end
  end

  @doc "Formats the first 16 bytes of a binary value as a UUIDv8 identifier."
  @spec uuid8(binary()) :: uuid8()
  def uuid8(<<time_low::32, time_mid::16, version_bits::16, variant_bits::16, node::48, _rest::binary>>) do
    version_bits = bor(band(version_bits, 0x0FFF), 0x8000)
    variant_bits = bor(band(variant_bits, 0x3FFF), 0x8000)

    <<time_low::32, time_mid::16, version_bits::16, variant_bits::16, node::48>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  def uuid8(value) when is_binary(value) do
    raise ArgumentError, "expected at least 16 bytes for a UUIDv8 identifier"
  end

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
      :error -> raise ArgumentError, "expected a valid UUIDv7 identifier"
    end
  end

  defp decode_uuid(uuid) do
    uuid
    |> String.replace("-", "")
    |> Base.decode16(case: :mixed)
  end

  defp format_uuid(<<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary-size(12)>>) do
    Enum.join([a, b, c, d, e], "-")
  end
end
