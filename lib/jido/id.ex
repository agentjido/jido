defmodule Jido.ID do
  @moduledoc false

  @max_unix_ts_ms 0xFFFFFFFFFFFF

  @doc false
  @spec uuid7() :: String.t()
  def uuid7 do
    uuid7(System.system_time(:millisecond), :crypto.strong_rand_bytes(10))
  end

  @doc false
  @spec uuid7(non_neg_integer(), <<_::80>>) :: String.t()
  def uuid7(timestamp_ms, random_bytes)
      when is_integer(timestamp_ms) and timestamp_ms in 0..@max_unix_ts_ms and
             byte_size(random_bytes) == 10 do
    # UUIDv7 has 74 random bits; 10 random bytes provide those bits plus 6 discarded bits.
    <<rand_a::12, rand_b::62, _unused::6>> = random_bytes

    <<timestamp_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  defp format_uuid(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
           e::binary-size(12)>>
       ) do
    a <> "-" <> b <> "-" <> c <> "-" <> d <> "-" <> e
  end
end
