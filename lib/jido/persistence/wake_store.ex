defmodule Jido.Persistence.WakeStore do
  @moduledoc false

  alias Jido.Agent.Ref
  alias Jido.Persistence.Store

  @prefix "jido:wakes:v1:"
  @max_attempts 4

  def list(instance) do
    with {:ok, config, namespace} <- config(instance) do
      case Store.read(config, key(namespace)) do
        {:ok, value, _condition} -> decode(value)
        {:error, :not_found} -> {:ok, []}
        {:error, _reason} = error -> error
      end
    end
  end

  def put(instance, entries) when is_list(entries) do
    update(instance, fn current -> merge(current, entries) end)
  end

  def delete_turn(instance, %Ref{} = ref, turn_id) do
    update(instance, fn current ->
      Enum.reject(current, &(&1.agent_ref == ref and &1.turn_id == turn_id))
    end)
  end

  def delete(instance, entry) do
    update(instance, fn current -> Enum.reject(current, &(&1 == entry)) end)
  end

  defp update(instance, fun), do: update(instance, fun, @max_attempts)

  defp update(_instance, _fun, 0), do: {:error, :wake_manifest_conflict}

  defp update(instance, fun, attempts) do
    with {:ok, config, namespace} <- config(instance),
         {:ok, current, condition} <- read(config, namespace),
         next <- fun.(current),
         {:ok, value} <- encode(next) do
      case Store.compare_and_swap(config, key(namespace), condition, value) do
        :ok -> :ok
        {:error, :conflict} -> update(instance, fun, attempts - 1)
        {:error, _reason} = error -> error
      end
    end
  end

  defp config(instance) do
    with namespace when is_binary(namespace) <-
           Jido.Instance.NamespaceRegistry.namespace(instance),
         {:ok, config, _instance} <- Jido.Persistence.resolve_source(instance, instance: instance) do
      {:ok, config, namespace}
    else
      nil -> {:error, :stable_namespace_required}
      {:error, _reason} = error -> error
    end
  end

  defp read(config, namespace) do
    case Store.read(config, key(namespace)) do
      {:ok, value, condition} ->
        with {:ok, entries} <- decode(value), do: {:ok, entries, condition}

      {:error, :not_found} ->
        {:ok, [], :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  defp merge(current, entries) do
    (current ++ entries)
    |> Enum.uniq_by(&{&1.agent_ref, &1.turn_id, &1.wait_id, &1.deadline})
    |> Enum.sort_by(&{&1.deadline, &1.turn_id, &1.wait_id})
  end

  defp encode(entries) do
    encoded =
      Enum.map(entries, fn entry ->
        %{entry | agent_ref: Ref.to_map!(entry.agent_ref)}
      end)

    {:ok, :erlang.term_to_binary(%{format: 1, entries: encoded})}
  rescue
    error -> {:error, {:wake_manifest_encode_failed, error}}
  end

  defp decode(value) do
    with %{format: 1, entries: entries} <- :erlang.binary_to_term(value, [:safe]),
         true <- is_list(entries) do
      entries
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
        with %{agent_ref: ref_map, turn_id: turn_id, wait_id: wait_id, deadline: deadline} <- entry,
             {:ok, ref} <- Ref.from_map(ref_map),
             true <- is_binary(turn_id) and is_binary(wait_id) and is_integer(deadline) do
          {:cont, {:ok, [%{agent_ref: ref, turn_id: turn_id, wait_id: wait_id, deadline: deadline} | acc]}}
        else
          _ -> {:halt, {:error, :invalid_wake_manifest}}
        end
      end)
      |> then(fn
        {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
        error -> error
      end)
    else
      _ -> {:error, :invalid_wake_manifest}
    end
  rescue
    ArgumentError -> {:error, :invalid_wake_manifest}
  end

  defp key(namespace), do: @prefix <> Base.url_encode64(namespace, padding: false)
end
