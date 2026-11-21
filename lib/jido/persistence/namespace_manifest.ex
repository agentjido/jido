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
    with {:ok, status} <- check(config, namespace) do
      confirm(config, namespace, status)
    end
  end

  def check(%Config{} = config, namespace) do
    case read(config, namespace) do
      {:ok, actual} ->
        expected = build(config, namespace)

        if actual === expected,
          do: {:ok, :pinned},
          else: {:error, {:persistence_namespace_mismatch, expected, actual}}

      {:error, :not_found} ->
        {:ok, :missing}

      {:error, _reason} = error ->
        error
    end
  end

  def confirm(_config, _namespace, :pinned), do: :ok

  def confirm(%Config{} = config, namespace, :missing) do
    with {:ok, bytes} <- Codec.JSON.encode(build(config, namespace)) do
      case Store.compare_and_swap(config.store, key(namespace), :not_found, bytes) do
        :ok -> :ok
        {:error, :conflict} -> confirm_after_conflict(config, namespace)
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

  defp confirm_after_conflict(config, namespace) do
    case check(config, namespace) do
      {:ok, :pinned} -> :ok
      {:ok, :missing} -> {:error, :conflict}
      {:error, _reason} = error -> error
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
