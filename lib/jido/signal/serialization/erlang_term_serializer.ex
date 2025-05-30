defmodule Jido.Signal.Serialization.ErlangTermSerializer do
  @moduledoc """
  A serializer that uses Erlang's built-in term format.

  This serializer is particularly useful for Erlang/Elixir clusters where
  data needs to be passed between nodes efficiently. The Erlang term format
  preserves the exact structure and types of Elixir/Erlang data.

  ## Features

  - Preserves exact data types (atoms, tuples, etc.)
  - Efficient for inter-node communication
  - Compact binary representation
  - No intermediate transformations needed

  ## Usage

      # Configure as default serializer
      config :jido, :default_serializer, Jido.Signal.Serialization.ErlangTermSerializer

      # Or use explicitly
      Signal.serialize(signal, serializer: Jido.Signal.Serialization.ErlangTermSerializer)
  """

  @behaviour Jido.Signal.Serialization.Serializer

  alias Jido.Signal.Serialization.TypeProvider

  @doc """
  Serialize given term to Erlang binary format.
  """
  @impl true
  def serialize(term, _opts \\ []) do
    {:ok, :erlang.term_to_binary(term, [:compressed])}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Deserialize given Erlang binary data back to the original term.

  For Erlang terms, type conversion is handled automatically since
  the format preserves the original structure. However, if a specific
  type is requested, we can still convert it.
  """
  @impl true
  def deserialize(binary, config \\ []) do
    result = :erlang.binary_to_term(binary, [:safe])

    # If a specific type is requested, convert to that type
    case Keyword.get(config, :type) do
      nil ->
        {:ok, result}

      type_str ->
        type_provider = Keyword.get(config, :type_provider, TypeProvider)

        converted_result =
          if is_map(result) and not is_struct(result) do
            # Convert map to struct if needed
            target_struct = type_provider.to_struct(type_str)
            struct(target_struct.__struct__, result)
          else
            result
          end

        {:ok, converted_result}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Checks if the given binary is a valid Erlang term.
  """
  @spec valid_erlang_term?(binary()) :: boolean()
  def valid_erlang_term?(binary) when is_binary(binary) do
    try do
      :erlang.binary_to_term(binary, [:safe])
      true
    rescue
      _ -> false
    end
  end

  def valid_erlang_term?(_), do: false
end
