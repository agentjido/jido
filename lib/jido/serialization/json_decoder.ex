#
# Json Decoder from Commanded: https://github.com/commanded/commanded/blob/master/lib/commanded/serialization/json_decoder.ex
# License: MIT
#
defprotocol Jido.Serialization.JsonDecoder do
  @doc """
  Protocol to allow additional decoding of a value that has been deserialized
  using the `Jido.Serialization.JsonSerializer`.

  The protocol is optional. The default behaviour is to to return the value if
  an explicit protocol is not defined.
  """
  @fallback_to_any true
  def decode(data)
end

defimpl Jido.Serialization.JsonDecoder, for: Any do
  @moduledoc """
  Null decoder for values that require no additional decoding.

  Returns the data exactly as provided.
  """
  def decode(data), do: data
end
