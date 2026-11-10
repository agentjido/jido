defmodule Jido.Codec.Index do
  @moduledoc false

  @type metadata :: %{
          required(:type) => String.t(),
          required(:vsn) => pos_integer(),
          required(:module) => module(),
          optional(:target) => module() | nil
        }

  @type t :: %__MODULE__{
          codecs: %{{String.t(), pos_integer()} => module()},
          encoders: %{module() => module()}
        }

  @enforce_keys [:codecs, :encoders]
  defstruct @enforce_keys

  @spec new([metadata()]) :: {:ok, t()} | {:error, term()}
  def new(metadata) when is_list(metadata) do
    metadata = Enum.sort_by(metadata, &{&1.type, &1.vsn, Atom.to_string(&1.module)})

    with :ok <- unique(metadata, &{&1.type, &1.vsn}, :duplicate_codec),
         :ok <- unique_targets(metadata) do
      {:ok,
       %__MODULE__{
         codecs: Map.new(metadata, &{{&1.type, &1.vsn}, &1.module}),
         encoders:
           metadata
           |> Enum.reject(&is_nil(Map.get(&1, :target)))
           |> Map.new(&{&1.target, &1.module})
       }}
    end
  end

  def new(_metadata), do: {:error, :invalid_codec_metadata}

  @spec new!([metadata()]) :: t()
  def new!(metadata) do
    case new(metadata) do
      {:ok, index} -> index
      {:error, reason} -> raise ArgumentError, "invalid Codec Index: #{inspect(reason)}"
    end
  end

  @spec encoder(t(), term()) :: {:ok, module()} | {:error, :unknown_encoder}
  def encoder(%__MODULE__{encoders: encoders}, %{__struct__: struct}) do
    case Map.fetch(encoders, struct) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_encoder}
    end
  end

  def encoder(%__MODULE__{}, _value), do: {:error, :unknown_encoder}

  @spec codec(t(), String.t(), pos_integer()) :: {:ok, module()} | {:error, :unknown_codec}
  def codec(%__MODULE__{codecs: codecs}, type, vsn) do
    case Map.fetch(codecs, {type, vsn}) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_codec}
    end
  end

  @spec versions(t(), String.t()) :: [pos_integer()]
  def versions(%__MODULE__{codecs: codecs}, type) do
    codecs
    |> Map.keys()
    |> Enum.flat_map(fn {entry_type, vsn} -> if entry_type == type, do: [vsn], else: [] end)
    |> Enum.sort()
  end

  defp unique_targets(metadata) do
    metadata
    |> Enum.reject(&is_nil(Map.get(&1, :target)))
    |> unique(& &1.target, :duplicate_encoder_target)
  end

  defp unique(values, key, tag) do
    duplicate =
      values
      |> Enum.group_by(key)
      |> Enum.find_value(fn {entry_key, grouped} -> if length(grouped) > 1, do: entry_key end)

    if duplicate, do: {:error, {tag, duplicate}}, else: :ok
  end
end
