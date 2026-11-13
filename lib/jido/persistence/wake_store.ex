defmodule Jido.Persistence.WakeStore do
  @moduledoc false

  alias Jido.Agent.Address
  alias Jido.Persistence.{Config, Store}

  @format 3
  @prefix "jido:wake:v3:"
  @bucket_ms 60_000
  @shard_count 64
  @max_attempts 8

  def list(instance) do
    case config(instance) do
      {:ok, config, namespace} -> list_config(config, namespace)
      {:error, :persistence_not_configured} -> {:ok, []}
      {:error, _reason} = error -> error
    end
  end

  defp list_config(config, namespace) do
    with {:ok, index, _condition} <- read_index(config, namespace) do
      index
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce_while({:ok, []}, fn {bucket, shards}, {:ok, entries} ->
        case read_shards(config, namespace, bucket, shards) do
          {:ok, found} -> {:cont, {:ok, found ++ entries}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> then(fn
        {:ok, entries} -> {:ok, Enum.sort_by(entries, &{&1.deadline, &1.turn_id, &1.wait_id})}
        error -> error
      end)
    end
  end

  def put(instance, entries) when is_list(entries) do
    with {:ok, config, namespace} <- config(instance),
         {:ok, groups} <- group_entries(entries),
         {:ok, generations} <- write_groups(config, namespace, groups),
         :ok <- add_groups_to_index(config, namespace, generations) do
      :ok
    end
  end

  def delete_turn(instance, %Address{} = address, turn_id) do
    with {:ok, entries} <- list(instance) do
      entries
      |> Enum.filter(&(&1.agent_address == address and &1.turn_id == turn_id))
      |> Enum.reduce_while(:ok, fn entry, :ok ->
        case delete(instance, entry) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  def delete(instance, entry) do
    with {:ok, config, namespace} <- config(instance),
         {:ok, bucket, shard} <- location(entry),
         {:ok, empty?, generation} <-
           remove_entry(config, namespace, bucket, shard, entry, @max_attempts),
         :ok <- maybe_remove_from_index(config, namespace, bucket, shard, empty?, generation) do
      :ok
    end
  end

  defp write_groups(config, namespace, groups) do
    Enum.reduce_while(groups, {:ok, %{}}, fn {{bucket, shard}, entries}, {:ok, generations} ->
      case merge_shard(config, namespace, bucket, shard, entries, @max_attempts) do
        {:ok, generation} ->
          {:cont, {:ok, Map.put(generations, {bucket, shard}, generation)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp merge_shard(_config, _namespace, _bucket, _shard, _entries, 0),
    do: {:error, :wake_shard_conflict}

  defp merge_shard(config, namespace, bucket, shard, entries, attempts) do
    with {:ok, current, generation, condition} <- read_shard(config, namespace, bucket, shard),
         next <- merge(current, entries) do
      if next == current do
        {:ok, generation}
      else
        next_generation = generation + 1

        with {:ok, bytes} <- encode(config, bucket, shard, next_generation, next) do
          case Store.compare_and_swap(config.store, shard_key(namespace, bucket, shard), condition, bytes) do
            :ok -> {:ok, next_generation}
            {:error, :conflict} -> merge_shard(config, namespace, bucket, shard, entries, attempts - 1)
            {:error, _reason} = error -> error
          end
        end
      end
    end
  end

  defp remove_entry(_config, _namespace, _bucket, _shard, _entry, 0),
    do: {:error, :wake_shard_conflict}

  defp remove_entry(config, namespace, bucket, shard, entry, attempts) do
    with {:ok, current, generation, condition} <- read_shard(config, namespace, bucket, shard),
         next <- Enum.reject(current, &(&1 == entry)) do
      if next == current do
        {:ok, next == [], generation}
      else
        next_generation = generation + 1

        with {:ok, bytes} <- encode(config, bucket, shard, next_generation, next) do
          case Store.compare_and_swap(config.store, shard_key(namespace, bucket, shard), condition, bytes) do
            :ok -> {:ok, next == [], next_generation}
            {:error, :conflict} -> remove_entry(config, namespace, bucket, shard, entry, attempts - 1)
            {:error, _reason} = error -> error
          end
        end
      end
    end
  end

  defp add_groups_to_index(config, namespace, generations) do
    additions =
      Enum.reduce(generations, %{}, fn {{bucket, shard}, generation}, acc ->
        Map.update(acc, bucket, %{shard => generation}, &Map.put(&1, shard, generation))
      end)

    update_index(config, namespace, fn index ->
      Map.merge(index, additions, fn _bucket, current, added ->
        Map.merge(current, added, fn _shard, left, right -> max(left, right) end)
      end)
    end)
  end

  defp maybe_remove_from_index(_config, _namespace, _bucket, _shard, false, _generation), do: :ok

  defp maybe_remove_from_index(config, namespace, bucket, shard, true, generation) do
    update_index(config, namespace, fn index ->
      case Map.get(index, bucket) do
        nil ->
          index

        shards ->
          case Map.get(shards, shard) do
            indexed_generation when is_integer(indexed_generation) and indexed_generation <= generation ->
              remaining = Map.delete(shards, shard)
              if map_size(remaining) == 0, do: Map.delete(index, bucket), else: Map.put(index, bucket, remaining)

            _newer_or_missing ->
              index
          end
      end
    end)
  end

  defp update_index(config, namespace, fun), do: update_index(config, namespace, fun, @max_attempts)
  defp update_index(_config, _namespace, _fun, 0), do: {:error, :wake_index_conflict}

  defp update_index(config, namespace, fun, attempts) do
    with {:ok, current, condition} <- read_index(config, namespace),
         next <- fun.(current) do
      if next == current do
        :ok
      else
        with {:ok, bytes} <- encode_index(config, next) do
          case Store.compare_and_swap(config.store, index_key(namespace), condition, bytes) do
            :ok -> :ok
            {:error, :conflict} -> update_index(config, namespace, fun, attempts - 1)
            {:error, _reason} = error -> error
          end
        end
      end
    end
  end

  defp read_shards(config, namespace, bucket, shards) do
    Enum.reduce_while(Map.keys(shards), {:ok, []}, fn shard, {:ok, entries} ->
      case read_shard(config, namespace, bucket, shard) do
        {:ok, found, _generation, _condition} -> {:cont, {:ok, found ++ entries}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp read_shard(config, namespace, bucket, shard) do
    case Store.read(config.store, shard_key(namespace, bucket, shard)) do
      {:ok, bytes, condition} ->
        with {:ok, entries, generation} <- decode(config, bytes, bucket, shard),
             do: {:ok, entries, generation, condition}

      {:error, :not_found} ->
        {:ok, [], 0, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  defp read_index(config, namespace) do
    case Store.read(config.store, index_key(namespace)) do
      {:ok, bytes, condition} ->
        with {:ok, index} <- decode_index(config, bytes), do: {:ok, index, condition}

      {:error, :not_found} ->
        {:ok, %{}, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  defp group_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, groups} ->
      case location(entry) do
        {:ok, bucket, shard} ->
          {:cont, {:ok, Map.update(groups, {bucket, shard}, [entry], &[entry | &1])}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp location(%{agent_address: %Address{} = address, turn_id: turn_id, wait_id: wait_id, deadline: deadline})
       when is_binary(turn_id) and is_binary(wait_id) and is_integer(deadline) do
    bucket = div(deadline, @bucket_ms)
    shard = :erlang.phash2({Address.to_map!(address), turn_id, wait_id}, @shard_count)
    {:ok, bucket, shard}
  end

  defp location(_entry), do: {:error, :invalid_wake_entry}

  defp merge(current, entries) do
    (current ++ entries)
    |> Enum.uniq_by(&{&1.agent_address, &1.turn_id, &1.wait_id, &1.deadline})
    |> Enum.sort_by(&{&1.deadline, &1.turn_id, &1.wait_id})
  end

  defp encode(config, bucket, shard, generation, entries) do
    # Keep the version-3 storage key so existing durable wake records remain readable.
    encoded =
      Enum.map(entries, fn entry ->
        entry
        |> Map.put(:agent_ref, Address.to_map!(entry.agent_address))
        |> Map.delete(:agent_address)
      end)

    Config.encode(config, %{
      format: @format,
      bucket: bucket,
      shard: shard,
      generation: generation,
      entries: encoded
    })
  end

  defp decode(config, bytes, bucket, shard) do
    with {:ok,
          %{
            format: @format,
            bucket: ^bucket,
            shard: ^shard,
            generation: generation,
            entries: entries
          }} <-
           Config.decode(config, bytes, trusted: true),
         true <- is_integer(generation) and generation > 0,
         true <- is_list(entries) do
      with {:ok, decoded} <- decode_entries(entries), do: {:ok, decoded, generation}
    else
      _ -> {:error, :invalid_wake_shard}
    end
  end

  defp decode_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      with %{agent_ref: address_map, turn_id: turn_id, wait_id: wait_id, deadline: deadline} <- entry,
           {:ok, address} <- Address.from_map(address_map),
           true <- is_binary(turn_id) and is_binary(wait_id) and is_integer(deadline) do
        {:cont, {:ok, [%{agent_address: address, turn_id: turn_id, wait_id: wait_id, deadline: deadline} | acc]}}
      else
        _ -> {:halt, {:error, :invalid_wake_entry}}
      end
    end)
    |> then(fn
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end)
  end

  defp encode_index(config, index) do
    Config.encode(config, %{format: @format, buckets: index})
  end

  defp decode_index(config, bytes) do
    with {:ok, %{format: @format, buckets: buckets}} <- Config.decode(config, bytes, trusted: true),
         true <- is_map(buckets) do
      Enum.reduce_while(buckets, {:ok, %{}}, fn {bucket, shards}, {:ok, index} ->
        valid_shards? =
          is_map(shards) and
            Enum.all?(shards, fn {shard, generation} ->
              is_integer(shard) and shard >= 0 and shard < @shard_count and
                is_integer(generation) and generation > 0
            end)

        if is_integer(bucket) and valid_shards? do
          {:cont, {:ok, Map.put(index, bucket, shards)}}
        else
          {:halt, {:error, :invalid_wake_index}}
        end
      end)
    else
      _ -> {:error, :invalid_wake_index}
    end
  end

  defp config(instance) do
    with {:ok, %Config{} = config, _instance} <-
           Jido.Persistence.resolve_source(instance, instance: instance),
         namespace when is_binary(namespace) <- Jido.Instance.NamespaceRegistry.namespace(instance) do
      {:ok, config, namespace}
    else
      nil -> {:error, :stable_namespace_required}
      {:error, _reason} = error -> error
    end
  end

  defp index_key(namespace), do: namespace_prefix(namespace) <> ":index"

  defp shard_key(namespace, bucket, shard),
    do:
      namespace_prefix(namespace) <>
        ":bucket:" <> Integer.to_string(bucket) <> ":shard:" <> Integer.to_string(shard)

  defp namespace_prefix(namespace), do: @prefix <> Base.url_encode64(namespace, padding: false)
end
