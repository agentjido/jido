defprotocol Jido.Codec.Encoder do
  @moduledoc """
  Selects the current write codec for a runtime value.

  Historical document versions do not implement this protocol. The Registry
  remains a fallback for codecs that are loaded after protocol consolidation.
  """

  @fallback_to_any true

  @doc "Returns the current codec module for the runtime value."
  @spec codec(term()) :: {:ok, module()} | :error
  def codec(value)
end

defimpl Jido.Codec.Encoder, for: Any do
  def codec(_value), do: :error
end
