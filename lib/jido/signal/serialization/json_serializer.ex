#
# Json Serializer from Commanded: https://github.com/commanded/commanded/blob/master/lib/commanded/serialization/json_serializer.ex
# License: MIT
#
if Code.ensure_loaded?(Jason) do
  defmodule Jido.Signal.Serialization.JsonSerializer do
    @moduledoc """
    A serializer that uses the JSON format and Jason library.
    """

    @behaviour Jido.Signal.Serialization.Serializer

    alias Jido.Signal.Serialization.TypeProvider
    alias Jido.Signal.Serialization.JsonDecoder

    @doc """
    Serialize given term to JSON binary data.
    """
    @impl true
    def serialize(term, _opts \\ []) do
      {:ok, Jason.encode!(term)}
    rescue
      e -> {:error, Exception.message(e)}
    end

    @doc """
    Deserialize given JSON binary data to the expected type.
    """
    @impl true
    def deserialize(binary, config \\ []) do
      {type, opts} =
        case Keyword.get(config, :type) do
          nil ->
            {nil, []}

          type_str ->
            # Check if the module exists before trying to convert to a struct
            module_name = String.to_atom(type_str)

            if Code.ensure_loaded?(module_name) do
              type_provider = Keyword.get(config, :type_provider, TypeProvider)
              {type_provider.to_struct(type_str), [keys: :atoms]}
            else
              raise ArgumentError, "Cannot deserialize to non-existent module: #{type_str}"
            end
        end

      result =
        binary
        |> Jason.decode!(opts)
        |> to_struct(type)
        |> JsonDecoder.decode()

      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end

    # Legacy API for backward compatibility
    @doc false
    def serialize_legacy(term) do
      case serialize(term) do
        {:ok, result} -> result
        {:error, _} -> raise "Serialization failed"
      end
    end

    @doc false
    def deserialize_legacy(binary, config \\ []) do
      case deserialize(binary, config) do
        {:ok, result} -> result
        {:error, reason} -> raise reason
      end
    end

    defp to_struct(data, nil), do: data

    defp to_struct(data, struct) when is_atom(struct) do
      # Check if the module exists to prevent UndefinedFunctionError
      if Code.ensure_loaded?(struct) do
        struct(struct, data)
      else
        raise ArgumentError, "Cannot deserialize to non-existent module: #{inspect(struct)}"
      end
    end

    # Handle the case where struct is already a struct type (not a module name)
    defp to_struct(data, %type{} = _struct) do
      struct(type, data)
    end
  end
end
