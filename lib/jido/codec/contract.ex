defmodule Jido.Codec.Contract do
  @moduledoc """
  Defines the contract for one versioned document codec.

  A current writer publishes a runtime `target/0` and implements both
  `encode/2` and `decode/2`. A historical reader returns `nil` from `target/0`
  and implements only `decode/2`.

  Callbacks receive an explicit Catalog or `:current`. Use `Jido.Codec.Reference`
  and `Jido.Codec.Value` for reference lookup. With `:current`, each lookup reads
  the current publication; the operation does not pin a Catalog.
  """

  @typedoc "A JSON object produced or consumed by a document codec."
  @type document :: %{required(String.t()) => term()}

  @doc "Returns the stable wire type owned by the codec."
  @callback type() :: String.t()

  @doc "Returns the positive wire version owned by the codec."
  @callback version() :: pos_integer()

  @doc "Returns the current writer target, or nil for a historical reader."
  @callback target() :: module() | nil

  @doc "Encodes one runtime value as a versioned document."
  @callback encode(term(), Jido.Catalog.source()) ::
              {:ok, document()} | {:error, Exception.t()}

  @doc "Decodes one versioned document through a trusted Catalog."
  @callback decode(term(), Jido.Catalog.source()) ::
              {:ok, struct()} | {:error, [Jido.Codec.Issue.t()]}

  @optional_callbacks encode: 2

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
    {:ok, %{type: module.type(), vsn: module.version(), target: module.target()}}
  rescue
    error -> {:error, {:metadata_failure, :error, error}}
  catch
    kind, reason -> {:error, {:metadata_failure, kind, reason}}
  end

  defp validate_metadata(%{type: type, vsn: vsn} = metadata)
       when is_binary(type) and byte_size(type) in 1..255 and is_integer(vsn) and vsn > 0 do
    target = Map.get(metadata, :target)

    if String.valid?(type) and (is_nil(target) or valid_module?(target)),
      do: {:ok, %{type: type, vsn: vsn, target: target}},
      else: {:error, {:invalid_metadata, metadata}}
  end

  defp validate_metadata(metadata), do: {:error, {:invalid_metadata, metadata}}

  defp supports?(module, :decode, _metadata),
    do: function_exported?(module, :decode, 2)

  defp supports?(module, :encode, _metadata),
    do: function_exported?(module, :encode, 2)

  defp supports?(module, :discovery, %{target: nil}),
    do: function_exported?(module, :decode, 2)

  defp supports?(module, :discovery, _metadata),
    do:
      function_exported?(module, :decode, 2) and
        function_exported?(module, :encode, 2)

  defp valid_module?(value), do: is_atom(value) and value not in [nil, true, false]
end
