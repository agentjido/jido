defmodule Jido.Authoring.Codec do
  @moduledoc false

  @type operation :: :decode | :encode | :discovery
  @type error ::
          :invalid_contract
          | {:invalid_metadata, term()}
          | {:metadata_failure, :error | :exit | :throw, term()}

  @doc false
  @spec metadata(module(), operation()) :: {:ok, map()} | {:error, error()}
  def metadata(module, operation \\ :discovery)

  def metadata(module, operation)
      when is_atom(module) and operation in [:decode, :encode, :discovery] do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :__jido_authoring_codec__, 0),
         {:ok, metadata} <- call_metadata(module),
         {:ok, metadata} <- validate_metadata(metadata),
         true <- supports?(module, operation, metadata) do
      {:ok, metadata}
    else
      false -> {:error, :invalid_contract}
      {:error, _reason} = error -> error
    end
  end

  def metadata(_module, _operation), do: {:error, :invalid_contract}

  defp call_metadata(module) do
    {:ok, module.__jido_authoring_codec__()}
  rescue
    error -> {:error, {:metadata_failure, :error, error}}
  catch
    kind, reason -> {:error, {:metadata_failure, kind, reason}}
  end

  defp validate_metadata(%{type: type, vsn: vsn} = metadata)
       when is_binary(type) and byte_size(type) in 1..255 and is_integer(vsn) and vsn > 0 do
    encoder = Map.get(metadata, :encoder)

    if String.valid?(type) and (is_nil(encoder) or valid_module?(encoder)),
      do: {:ok, %{type: type, vsn: vsn, encoder: encoder}},
      else: {:error, {:invalid_metadata, metadata}}
  end

  defp validate_metadata(metadata), do: {:error, {:invalid_metadata, metadata}}

  defp supports?(module, :decode, _metadata),
    do: function_exported?(module, :decode_document, 2)

  defp supports?(module, :encode, _metadata),
    do: function_exported?(module, :encode_document, 2)

  defp supports?(module, :discovery, %{encoder: nil}),
    do: function_exported?(module, :decode_document, 2)

  defp supports?(module, :discovery, _metadata),
    do:
      function_exported?(module, :decode_document, 2) and
        function_exported?(module, :encode_document, 2)

  defp valid_module?(value), do: is_atom(value) and value not in [nil, true, false]
end
