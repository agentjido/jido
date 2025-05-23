#
# Generic Serialization Behavior
#
defmodule Jido.Signal.Serialization.Serializer do
  @moduledoc """
  Behaviour for serialization strategies.

  This behavior defines a common interface for different serialization formats
  such as JSON, Erlang Term format, and MessagePack.

  ## Implementation Examples

      defmodule MySerializer do
        @behaviour Jido.Signal.Serialization.Serializer

        def serialize(data, _opts \\ []) do
          # Your serialization logic here
          {:ok, serialized_data}
        end

        def deserialize(binary, opts \\ []) do
          # Your deserialization logic here
          {:ok, deserialized_data}
        end
      end

  ## Configuration

  The default serializer can be configured in your application config:

      config :jido, :default_serializer, MySerializer

  You can also override the serializer per operation by passing the `:serializer` option:

      Signal.serialize(signal, serializer: MySerializer)
      Signal.deserialize(binary, serializer: MySerializer)
  """

  @type serializable :: term()
  @type serialized :: binary()
  @type opts :: keyword()
  @type result :: {:ok, term()} | {:error, term()}

  @doc """
  Serialize the given term to binary format.

  ## Parameters

    * `data` - The data to serialize
    * `opts` - Optional configuration (e.g., type information)

  ## Returns

    * `{:ok, binary}` - Success with serialized binary
    * `{:error, reason}` - Failure with reason
  """
  @callback serialize(serializable(), opts()) :: {:ok, serialized()} | {:error, term()}

  @doc """
  Deserialize the given binary data back to the original format.

  ## Parameters

    * `binary` - The serialized binary data
    * `opts` - Optional configuration (e.g., type information, type provider)

  ## Returns

    * `{:ok, term}` - Success with deserialized data
    * `{:error, reason}` - Failure with reason
  """
  @callback deserialize(serialized(), opts()) :: result()

  @doc """
  Get the configured default serializer.
  """
  @spec default_serializer() :: module()
  def default_serializer do
    Jido.Signal.Serialization.Config.default_serializer()
  end

  @doc """
  Serialize data using the specified or default serializer.
  """
  @spec serialize(serializable(), opts()) :: {:ok, serialized()} | {:error, term()}
  def serialize(data, opts \\ []) do
    serializer = Keyword.get(opts, :serializer, default_serializer())
    serializer.serialize(data, opts)
  end

  @doc """
  Deserialize data using the specified or default serializer.
  """
  @spec deserialize(serialized(), opts()) :: result()
  def deserialize(binary, opts \\ []) do
    serializer = Keyword.get(opts, :serializer, default_serializer())
    serializer.deserialize(binary, opts)
  end
end
