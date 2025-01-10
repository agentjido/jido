#
# Json Decoder from Commanded: https://github.com/commanded/commanded/blob/master/lib/commanded/serialization/json_decoder.ex
# License: MIT
#
defprotocol Jido.Serialization.JsonDecoder do
  @moduledoc """
  Protocol to allow additional decoding of a value that has been deserialized from JSON.

  This protocol enables custom decoding logic to be applied after JSON deserialization.
  It is particularly useful when you need to transform or validate data after it has been
  deserialized from JSON format.

  ## Example

      defmodule MyStruct do
        @derive Jason.Encoder
        defstruct [:value]
      end

      # Custom decoder implementation that doubles numeric values
      defimpl Jido.Serialization.JsonDecoder, for: MyStruct do
        def decode(%MyStruct{value: value} = data) when is_number(value) do
          %MyStruct{value: value * 2}
        end

        def decode(data), do: data
      end

  The protocol is optional with a fallback implementation for Any that returns the data unchanged.
  """

  @doc """
  Decodes data that has been deserialized using the `Jido.Serialization.JsonSerializer`.

  This function is called after JSON deserialization to perform any additional data transformations
  or validations needed for the specific data type.

  ## Parameters

    * `data` - The deserialized data to be decoded

  ## Returns

    The decoded data, which can be transformed in any way appropriate for the implementing type.
    The default implementation for Any simply returns the data unchanged.
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
