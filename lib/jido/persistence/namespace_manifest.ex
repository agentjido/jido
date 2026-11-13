defmodule Jido.Persistence.NamespaceManifest do
  @moduledoc false

  alias Jido.Persistence.{Codec, Config, Store}

  @format 1
  @key_prefix "jido:namespace:v3:"
  @wake_bucket_ms 60_000
  @wake_shards 64

  @spec open(Config.t() | nil, String.t() | nil) :: :ok | {:error, term()}
  def open(nil, _namespace), do: :ok

  def open(%Config{}, namespace) when not is_binary(namespace),
    do: {:error, :stable_namespace_required}

  def open(%Config{} = config, namespace) do
    manifest = build(config, namespace)

    with {:ok, bytes} <- Codec.JSON.encode(manifest) do
      case Store.read(config.store, key(namespace)) do
        {:ok, stored, _condition} -> compare(stored, manifest)
        {:error, :not_found} -> create(config, namespace, bytes)
        {:error, _reason} = error -> error
      end
    end
  end

  @spec read(Config.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def read(%Config{} = config, namespace) when is_binary(namespace) do
    with {:ok, bytes, _condition} <- Store.read(config.store, key(namespace)),
         {:ok, manifest} <- decode(bytes) do
      {:ok, manifest}
    end
  end

  defp create(config, namespace, bytes) do
    case Store.compare_and_swap(config.store, key(namespace), :not_found, bytes) do
      :ok -> :ok
      {:error, :conflict} -> open(config, namespace)
      {:error, _reason} = error -> error
    end
  end

  defp compare(bytes, expected) do
    with {:ok, actual} <- decode(bytes) do
      if actual == expected,
        do: :ok,
        else: {:error, {:persistence_namespace_mismatch, expected, actual}}
    end
  end

  defp decode(bytes) do
    case Codec.JSON.decode(bytes, []) do
      {:ok, %{format: @format} = manifest} -> {:ok, manifest}
      _other -> {:error, :invalid_persistence_namespace_manifest}
    end
  end

  defp build(%Config{codec: codec}, namespace) do
    %{
      format: @format,
      namespace: namespace,
      codec: %{id: codec.id(), version: codec.version()},
      records: %{agent: 3, execution: 3, wake: 3},
      wake: %{bucket_ms: @wake_bucket_ms, shards: @wake_shards}
    }
  end

  defp key(namespace), do: @key_prefix <> Base.url_encode64(namespace, padding: false)
end
