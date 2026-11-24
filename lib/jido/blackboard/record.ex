defmodule Jido.Blackboard.Record do
  @moduledoc false

  alias Jido.Agent.Address
  alias Jido.{Blackboard, Persistence}
  alias Jido.Persistence.{Config, Store}

  @format 1
  @deleted {@format, :deleted}

  def configure(instance, %Address{} = address, name) do
    case Persistence.resolve_config(:inherit, instance) do
      {:ok, %Config{} = profile} -> {:ok, {profile, key(address, name)}}
      {:ok, nil} -> {:error, :persistence_not_configured}
      {:error, _reason} = error -> error
    end
  end

  def open(nil, data), do: {:ok, data}

  def open(record, initial) do
    case read(record) do
      {:ok, previous, condition} ->
        data = %{initial | values: previous.values}
        with :ok <- write(record, condition, data), do: {:ok, data}

      {:error, :not_found} ->
        with :ok <- write(record, :not_found, initial), do: {:ok, initial}

      {:error, _reason} = error ->
        error
    end
  end

  def commit(nil, _current, _next), do: :ok

  def commit(record, current, next) do
    case read(record) do
      {:ok, ^current, condition} -> write(record, condition, next)
      {:ok, _other, _condition} -> {:error, :conflict}
      {:error, reason} when reason in [:not_found, :deleted] -> {:error, :conflict}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  def read({%Config{} = profile, key}) do
    with {:ok, bytes, condition} <- Store.read(profile.store, key),
         {:ok, term} <- Config.decode(profile, bytes) do
      decode(term, condition)
    end
  end

  def delete(record) do
    case read(record) do
      {:ok, _snapshot, condition} -> swap(record, condition, @deleted)
      {:error, :deleted} -> :ok
      {:error, :not_found} = error -> error
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp decode({@format, generation, version, values}, condition)
       when is_binary(generation) and byte_size(generation) > 0 and is_integer(version) and version >= 0 do
    with :ok <- Blackboard.validate_changes(values, []) do
      {:ok, %{generation: generation, version: version, values: values}, condition}
    end
  end

  defp decode(@deleted, _condition), do: {:error, :deleted}
  defp decode(_term, _condition), do: {:error, :invalid_board_record}

  defp write(record, condition, data),
    do: swap(record, condition, {@format, data.generation, data.version, data.values})

  defp swap({profile, key}, condition, term) do
    case Config.encode(profile, term) do
      {:ok, bytes} -> classify(Store.compare_and_swap(profile.store, key, condition, bytes))
      {:error, _reason} -> {:error, :invalid_request}
    end
  end

  defp classify(:ok), do: :ok
  defp classify({:error, :conflict} = error), do: error
  defp classify({:error, {:rejected, _reason}}), do: {:error, :unavailable}
  defp classify({:error, _reason}), do: {:error, :indeterminate}

  defp key(address, name) do
    encoded =
      {address.namespace, address.partition, address.id, name}
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    "jido:blackboard:v1:" <> encoded
  end
end
