defmodule Jido.Persistence.Config do
  @moduledoc """
  One validated persistence profile for a Jido instance.

  A profile combines one binary Store with one codec. Adapter declarations are
  shorthand for the default `Jido.Persistence.Codec.Term` codec. Use a unique
  keyword profile to select another codec:

      [store: {Jido.Persistence.File, path: "data/jido"},
       codec: Jido.Persistence.Codec.JSON]

  With the Term codec, set `:execution_compression` to `true` to compress
  prepared execution records, fact values, and event batches. It defaults to
  `false`. Both settings read compressed and uncompressed Term records.
  """

  alias Jido.Persistence.Codec
  alias Jido.Persistence.Codec.Term
  alias Jido.Persistence.Store

  @enforce_keys [:store, :codec]
  defstruct [:store, :codec, execution_compression: false]

  @type t :: %__MODULE__{store: Store.config(), codec: module(), execution_compression: boolean()}
  @profile_keys [:store, :codec, :execution_compression]

  @spec open(term()) :: {:ok, t() | nil} | {:error, term()}
  def open(nil), do: {:ok, nil}
  def open(false), do: {:ok, nil}
  def open(%__MODULE__{} = config), do: validate(config)

  def open(declaration) when is_list(declaration) do
    if Keyword.keyword?(declaration) and
         Enum.any?(@profile_keys, &Keyword.has_key?(declaration, &1)) do
      with :ok <- validate_profile_keys(declaration) do
        validate(%__MODULE__{
          store: Keyword.fetch!(declaration, :store),
          codec: Keyword.get(declaration, :codec, Term),
          execution_compression: Keyword.get(declaration, :execution_compression, false)
        })
      end
    else
      {:error, {:invalid_persistence_profile, declaration}}
    end
  end

  def open(declaration), do: validate(%__MODULE__{store: declaration, codec: Term})

  @spec normalize(term()) :: t() | nil
  def normalize(declaration) do
    case open(declaration) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "invalid Jido persistence profile: #{inspect(reason)}"
    end
  end

  @spec encode(t(), term()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{codec: codec}, value), do: codec.encode(value)

  @spec decode(t(), binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def decode(%__MODULE__{codec: codec}, bytes, opts \\ []), do: codec.decode(bytes, opts)

  defp validate(%__MODULE__{} = config) do
    with {:ok, store} <- Store.open(config.store),
         {:ok, codec} <- Codec.open(config.codec),
         :ok <- validate_compression(config.execution_compression, codec) do
      {:ok, %{config | store: store, codec: codec}}
    end
  end

  defp validate_compression(false, _codec), do: :ok
  defp validate_compression(true, Term), do: :ok
  defp validate_compression(true, codec), do: {:error, {:execution_compression_requires_term_codec, codec}}
  defp validate_compression(value, _codec), do: {:error, {:invalid_execution_compression, value}}

  defp validate_profile_keys(opts) do
    keys = Keyword.keys(opts)
    unknown = keys |> Enum.reject(&(&1 in @profile_keys)) |> Enum.uniq()
    duplicates = keys -- Enum.uniq(keys)

    cond do
      unknown != [] -> {:error, {:unknown_persistence_profile_options, unknown}}
      duplicates != [] -> {:error, {:duplicate_persistence_profile_options, Enum.uniq(duplicates)}}
      not Keyword.has_key?(opts, :store) -> {:error, {:missing_persistence_profile_option, :store}}
      true -> :ok
    end
  end
end
