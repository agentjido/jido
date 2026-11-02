defmodule Jido.Signal.UTF8 do
  @moduledoc false
  import Bitwise, only: [band: 2]

  @doc false
  @spec valid?(binary()) :: boolean()
  # Seven ASCII bytes fit in one small integer. Stop this scan at the first
  # non-ASCII chunk so Unicode data pays for only one failed chunk check.
  def valid?(<<chunk::56, rest::binary>>) when band(chunk, 0x80808080808080) == 0,
    do: valid?(rest)

  def valid?(rest), do: String.valid?(rest)
end
