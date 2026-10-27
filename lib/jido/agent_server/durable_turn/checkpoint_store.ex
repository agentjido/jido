defmodule Jido.AgentServer.DurableTurn.CheckpointStore do
  @moduledoc false
  alias Jido.Persistence.{AdapterOps, Store}
  alias Jido.Exec.Frame.Delta

  @prefix "jido:execution:"
  @fact_tag :jido_fact_value
  @fact_version 1
  @max_fact_delta_depth 32
  @fact_index_write_attempts 8

  def register(jido, id, config, owner \\ self()),
    do: Jido.RuntimeStore.put(jido, __MODULE__, id, {owner, config})

  # Terminal checkpoint collection is best effort. A failed physical delete
  # must not change a Turn result which is already durable in the Agent record.
  def collect(jido, id) do
    case Jido.RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, config}} when owner == self() ->
        with :ok <- Jido.RuntimeStore.delete_owned(jido, __MODULE__, id, owner),
             {:ok, _pid} <-
               Task.Supervisor.start_child(Jido.task_supervisor_name(jido), fn ->
                 delete_execution(config, id)
               end),
             do: :ok

      {:ok, _registration} ->
        {:error, :execution_owner_replaced}

      _missing ->
        {:error, :execution_store_unavailable}
    end
  end

  def append({:jido_execution, _, _, _, _} = id, events, jido) when is_list(events) do
    with {:ok, events} <- detach_join_values(events, id, jido),
         {:ok, config} <- config(jido, id),
         {:ok, batch_count, condition} <- read_batch_count(config, id) do
      append_batch(config, id, batch_count, condition, events)
    end
  end

  # Non-durable Turns share the Runner Store but do not persist execution events.
  def append(_id, _events, _jido), do: {:ok, 0}

  def stream({:jido_execution, _, _, _, _} = id, jido) do
    with {:ok, config} <- config(jido, id),
         {:ok, batch_count, _condition} <- read_batch_count(config, id),
         true <- batch_count > 0,
         {:ok, batches} <- read_batches(config, id, 1, batch_count, []) do
      batches
      |> Enum.reverse()
      |> Enum.concat()
      |> hydrate_join_values(id, jido)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def stream(_id, _jido), do: {:error, :not_found}

  def save_fact({:jido_execution, _, _, _, _} = id, hash, value, jido) do
    with {:ok, config} <- config(jido, id) do
      save_fact_value(config, id, hash, value)
    end
  end

  def save_fact(_id, _hash, _value, _jido), do: :ok

  def load_fact({:jido_execution, _, _, _, _} = id, hash, jido) do
    with {:ok, config} <- config(jido, id),
         {:ok, value, _depth} <- load_fact_value(config, id, hash, MapSet.new()) do
      {:ok, value}
    end
  end

  def load_fact(_id, _hash, _jido), do: {:error, :not_found}

  defp detach_join_values(events, id, jido) do
    Enum.reduce_while(events, {:ok, []}, fn
      %Runic.Workflow.Events.JoinCompleted{} = event, {:ok, detached} ->
        case save_fact(id, event.result_fact_hash, event.result_value, jido) do
          :ok -> {:cont, {:ok, [%{event | result_value: nil} | detached]}}
          {:error, _reason} = error -> {:halt, error}
        end

      event, {:ok, detached} ->
        {:cont, {:ok, [event | detached]}}
    end)
    |> case do
      {:ok, detached} -> {:ok, Enum.reverse(detached)}
      {:error, _reason} = error -> error
    end
  end

  defp hydrate_join_values(events, id, jido) do
    Enum.reduce_while(events, {:ok, []}, fn
      %Runic.Workflow.Events.JoinCompleted{result_value: nil} = event, {:ok, hydrated} ->
        case load_fact(id, event.result_fact_hash, jido) do
          {:ok, value} -> {:cont, {:ok, [%{event | result_value: value} | hydrated]}}
          {:error, _reason} = error -> {:halt, error}
        end

      event, {:ok, hydrated} ->
        {:cont, {:ok, [event | hydrated]}}
    end)
    |> case do
      {:ok, hydrated} -> {:ok, Enum.reverse(hydrated)}
      {:error, _reason} = error -> error
    end
  end

  def update_workflow(jido, id, transition) do
    case stream(id, jido) do
      {:ok, events} ->
        with {:ok, hydrated} <- hydrate_events(events, id, jido) do
          workflow =
            hydrated |> Runic.Workflow.from_events() |> Runic.Workflow.enable_event_emission()

          case transition.(workflow) do
            {:ok, ^workflow} ->
              {:ok, workflow}

            {:ok, next} ->
              events = Enum.reverse(next.uncommitted_events)

              with {:ok, _batch_count} <- persist_events(id, events, jido) do
                {:ok, %{next | uncommitted_events: []}}
              end

            error ->
              error
          end
        end

      {:error, :not_found} ->
        {:ok, nil}

      error ->
        error
    end
  end

  defp hydrate_events(events, id, jido) do
    Enum.reduce_while(events, {:ok, []}, fn
      %Runic.Workflow.Events.FactProduced{value: nil} = event, {:ok, hydrated} ->
        case load_fact(id, event.hash, jido) do
          {:ok, value} -> {:cont, {:ok, [%{event | value: value} | hydrated]}}
          {:error, _reason} = error -> {:halt, error}
        end

      event, {:ok, hydrated} ->
        {:cont, {:ok, [event | hydrated]}}
    end)
    |> case do
      {:ok, hydrated} -> {:ok, Enum.reverse(hydrated)}
      {:error, _reason} = error -> error
    end
  end

  defp persist_events(id, events, jido) do
    with :ok <- persist_event_facts(events, id, jido) do
      append(id, strip_event_fact_values(events), jido)
    end
  end

  defp persist_event_facts(events, id, jido) do
    Enum.reduce_while(events, :ok, fn
      %Runic.Workflow.Events.FactProduced{} = event, :ok ->
        case save_fact(id, event.hash, event.value, jido) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end

      _event, :ok ->
        {:cont, :ok}
    end)
  end

  defp strip_event_fact_values(events) do
    Enum.map(events, fn
      %Runic.Workflow.Events.FactProduced{} = event -> %{event | value: nil}
      event -> event
    end)
  end

  defp config(jido, id) do
    case Jido.RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, config}} ->
        if Process.alive?(owner), do: {:ok, config}, else: {:error, :execution_owner_lost}

      _ ->
        {:error, :execution_store_unavailable}
    end
  end

  defp append_batch(_config, _id, batch_count, _condition, []), do: {:ok, batch_count}

  defp append_batch(config, id, batch_count, condition, events) do
    next = batch_count + 1

    with :ok <-
           Store.compare_and_swap(
             config,
             batch_key(id, next),
             :not_found,
             :erlang.term_to_binary(events)
           ),
         :ok <- write_batch_count(config, id, condition, next) do
      {:ok, next}
    end
  end

  defp save_fact_value(config, id, hash, value) do
    case Store.read(config, fact_key(id, hash)) do
      {:ok, _bytes, _condition} ->
        accept_existing_fact(config, id, hash, value)

      {:error, :not_found} ->
        with {:ok, base_hash, head_condition} <- read_fact_head(config, id),
             {:ok, record} <- fact_record(config, id, base_hash, value),
             :ok <- record_fact_hash(config, id, hash) do
          case Store.compare_and_swap(
                 config,
                 fact_key(id, hash),
                 :not_found,
                 encode(record)
               ) do
            :ok -> advance_fact_head(config, id, head_condition, hash)
            {:error, :conflict} -> accept_existing_fact(config, id, hash, value)
            error -> error
          end
        end

      error ->
        error
    end
  end

  defp accept_existing_fact(config, id, hash, value) do
    with {:ok, stored, _depth} <- load_fact_value(config, id, hash, MapSet.new()),
         true <- stored === value do
      record_fact_hash(config, id, hash)
    else
      false -> {:error, :fact_value_conflict}
      error -> error
    end
  end

  defp fact_record(_config, _id, nil, value), do: {:ok, full_fact_record(value)}

  defp fact_record(config, id, base_hash, value) do
    with {:ok, base, depth} <- load_fact_value(config, id, base_hash, MapSet.new()) do
      full = full_fact_record(value)

      case Delta.encode(base, value) do
        {:delta, encoded} when depth < @max_fact_delta_depth ->
          delta =
            {@fact_tag, @fact_version, depth + 1, fact_digest(value), {:delta, base_hash},
             encoded}

          {:ok, if(encoded_size(delta) < encoded_size(full), do: delta, else: full)}

        _full ->
          {:ok, full}
      end
    end
  end

  defp full_fact_record(value),
    do: {@fact_tag, @fact_version, 0, fact_digest(value), :full, value}

  defp load_fact_value(config, id, hash, seen) do
    if MapSet.member?(seen, hash) do
      {:error, :invalid_execution_checkpoint}
    else
      with {:ok, bytes, _condition} <- Store.read(config, fact_key(id, hash)),
           {:ok, record} <- decode(bytes) do
        decode_fact_record(config, id, record, MapSet.put(seen, hash))
      end
    end
  end

  defp decode_fact_record(
         _config,
         _id,
         {@fact_tag, @fact_version, 0, digest, :full, value},
         _seen
       )
       when is_binary(digest) and byte_size(digest) == 32 do
    with :ok <- verify_fact_digest(value, digest), do: {:ok, value, 0}
  end

  defp decode_fact_record(
         config,
         id,
         {@fact_tag, @fact_version, depth, digest, {:delta, base_hash}, encoded},
         seen
       )
       when is_integer(depth) and depth > 0 and depth <= @max_fact_delta_depth and
              is_binary(digest) and byte_size(digest) == 32 do
    with {:ok, base, base_depth} <- load_fact_value(config, id, base_hash, seen),
         true <- depth == base_depth + 1,
         {:ok, value} <- Delta.decode(base, encoded),
         :ok <- verify_fact_digest(value, digest) do
      {:ok, value, depth}
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp decode_fact_record(_config, _id, _record, _seen),
    do: {:error, :invalid_execution_checkpoint}

  defp read_fact_head(config, id) do
    case Store.read(config, fact_head_key(id)) do
      {:ok, bytes, condition} ->
        case decode(bytes) do
          {:ok, {:jido_fact_head, 1, hash}} -> {:ok, hash, condition}
          _invalid -> {:error, :invalid_execution_checkpoint}
        end

      {:error, :not_found} ->
        {:ok, nil, :not_found}

      error ->
        error
    end
  end

  defp advance_fact_head(config, id, condition, hash) do
    case Store.compare_and_swap(
           config,
           fact_head_key(id),
           condition,
           encode({:jido_fact_head, 1, hash})
         ) do
      :ok -> :ok
      {:error, :conflict} -> :ok
      error -> error
    end
  end

  defp record_fact_hash(config, id, hash),
    do: record_fact_hash(config, id, hash, @fact_index_write_attempts)

  defp record_fact_hash(_config, _id, _hash, 0), do: {:error, :conflict}

  defp record_fact_hash(config, id, hash, attempts) do
    with {:ok, hashes, condition} <- read_fact_index(config, id) do
      if Enum.any?(hashes, &(&1 === hash)) do
        :ok
      else
        case Store.compare_and_swap(
               config,
               fact_index_key(id),
               condition,
               encode({:jido_fact_index, 1, [hash | hashes]})
             ) do
          :ok -> :ok
          {:error, :conflict} -> record_fact_hash(config, id, hash, attempts - 1)
          error -> error
        end
      end
    end
  end

  defp read_fact_index(config, id) do
    case Store.read(config, fact_index_key(id)) do
      {:ok, bytes, condition} ->
        case decode(bytes) do
          {:ok, {:jido_fact_index, 1, hashes}} when is_list(hashes) ->
            {:ok, hashes, condition}

          _invalid ->
            {:error, :invalid_execution_checkpoint}
        end

      {:error, :not_found} ->
        {:ok, [], :not_found}

      error ->
        error
    end
  end

  defp read_batch_count(config, id) do
    case Store.read(config, key(id)) do
      {:ok, bytes, condition} ->
        with {:ok, batch_count} when is_integer(batch_count) and batch_count >= 0 <- decode(bytes) do
          recover_tail(config, id, batch_count, condition)
        else
          _invalid -> {:error, :invalid_execution_checkpoint}
        end

      {:error, :not_found} ->
        recover_tail(config, id, 0, :not_found)

      error ->
        error
    end
  end

  # The event batch is the durable commit. Repair its count if the writer stopped
  # between the batch write and the count update.
  defp recover_tail(config, id, batch_count, condition) do
    next = batch_count + 1

    case Store.read(config, batch_key(id, next)) do
      {:ok, bytes, _chunk_condition} ->
        with {:ok, [_ | _]} <- decode(bytes),
             :ok <- write_batch_count(config, id, condition, next) do
          read_batch_count(config, id)
        end

      {:error, :not_found} ->
        {:ok, batch_count, condition}

      error ->
        error
    end
  end

  defp read_batches(_config, _id, index, last, batches) when index > last,
    do: {:ok, batches}

  defp read_batches(config, id, index, last, batches) do
    with {:ok, bytes, _condition} <- Store.read(config, batch_key(id, index)),
         {:ok, [_ | _] = events} <- decode(bytes) do
      read_batches(config, id, index + 1, last, [events | batches])
    end
  end

  defp write_batch_count(config, id, condition, batch_count) do
    Store.compare_and_swap(config, key(id), condition, encode(batch_count))
  end

  # Runic events contain domain atoms and code references. These are trusted
  # runtime records, not ingress payloads, so :safe cannot decode them.
  defp decode(bytes) when is_binary(bytes) do
    {:ok, :erlang.binary_to_term(bytes)}
  rescue
    ArgumentError -> {:error, :invalid_execution_checkpoint}
  end

  defp delete_execution(config, id) do
    with {:ok, batch_count, _condition} <- read_batch_count(config, id),
         {:ok, indexed_hashes, _condition} <- read_fact_index(config, id) do
      batch_keys = for index <- batch_count..1//-1, batch_count > 0, do: batch_key(id, index)
      fact_keys = for hash <- Enum.uniq(indexed_hashes), do: fact_key(id, hash)

      Enum.each(
        [key(id), fact_head_key(id), fact_index_key(id) | batch_keys ++ fact_keys],
        &delete_record(config, &1)
      )
    end
  end

  defp delete_record({adapter, opts}, key) do
    if function_exported?(adapter, :delete, 2),
      do: AdapterOps.protect(:delete, fn -> adapter.delete(key, opts) end)
  end

  defp key(id), do: @prefix <> Base.url_encode64(:erlang.term_to_binary(id), padding: false)

  defp batch_key(id, index), do: key(id) <> ":batches:" <> Integer.to_string(index)
  defp fact_head_key(id), do: key(id) <> ":facts:head"
  defp fact_index_key(id), do: key(id) <> ":facts:index"

  defp fact_key(id, hash) do
    key(id) <>
      ":facts:" <>
      Base.url_encode64(:erlang.term_to_binary(hash, [:deterministic]), padding: false)
  end

  defp fact_digest(value), do: :crypto.hash(:sha256, encode(value))

  defp verify_fact_digest(value, digest) do
    if fact_digest(value) == digest, do: :ok, else: {:error, :invalid_execution_checkpoint}
  end

  defp encode(value), do: :erlang.term_to_binary(value, [:deterministic])
  defp encoded_size(value), do: value |> encode() |> byte_size()
end
