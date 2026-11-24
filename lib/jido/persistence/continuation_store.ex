defmodule Jido.Persistence.ContinuationStore do
  @moduledoc false
  @behaviour Runic.Runner.Store

  alias Jido.Persistence.{Config, Store}
  alias Jido.Persistence.Codec.Term
  alias Jido.Exec.Runtime
  alias __MODULE__.JoinCompletedRef
  alias Runic.Workflow.{Fact, FactRef, FactResolver, Rehydration, RunnableCompleted}
  alias Runic.Workflow.Events.FactProduced

  @prefix "jido:execution:v3:"
  @fact_tag :jido_fact_value
  @fact_version 1
  @fact_index_write_attempts 8

  # Durable Flow Turns use the Agent persistence adapter. Ordinary Turns save
  # no graph.
  @impl true
  def init_store(opts), do: {:ok, Keyword.get(opts, :jido)}

  @impl true
  def for_workflow(id, jido), do: {id, jido}

  @impl true
  def save(_id, _log, _state), do: :ok

  @impl true
  def load(_id, _state), do: {:error, :not_found}

  @impl true
  def save_fact(hash, value, {id, jido}), do: save_fact(id, hash, value, jido)

  @impl true
  def load_fact(hash, {id, %Config{} = profile}), do: read_fact(profile, id, hash)
  def load_fact(hash, {id, jido}), do: load_fact(id, hash, jido)

  def read_fact(%Config{} = profile, id, hash), do: load_fact_value(profile, id, hash)

  def register(jido, id, config, owner \\ self()) do
    with {:ok, %Config{} = profile} <- Config.open(config) do
      Jido.Instance.RuntimeStore.put(jido, __MODULE__, id, {owner, profile})
    end
  end

  def prepare(jido, id, value) do
    with {:ok, config} <- config(jido, id),
         record = {:jido_execution_prepared, 3, value},
         {:ok, bytes} <- encode_payload(config, record) do
      case Store.compare_and_swap(config.store, prepared_key(id), :not_found, bytes) do
        :ok -> :ok
        {:error, :conflict} -> accept_prepared(config, id, record)
        {:error, _reason} = error -> error
      end
    end
  end

  # Terminal checkpoint collection is best effort. A failed physical delete
  # must not change a Turn result which is already durable in the Agent record.
  def collect(jido, id) do
    case Jido.Instance.RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, config}} when owner == self() ->
        with :ok <- Jido.Instance.RuntimeStore.delete_owned(jido, __MODULE__, id, owner),
             {:ok, _pid} <-
               Task.Supervisor.start_child(Jido.Instance.Names.task_supervisor(jido), fn ->
                 delete_execution(config, id)
               end),
             do: :ok

      {:ok, _registration} ->
        {:error, :execution_owner_replaced}

      _missing ->
        {:error, :execution_store_unavailable}
    end
  end

  @impl true
  def append(id, events, {id, jido}), do: append(id, events, jido)

  def append({:jido_execution, _, _, _, _} = id, events, jido) when is_list(events) do
    with {:ok, events} <- detach_join_values(events, id, jido),
         {:ok, config} <- config(jido, id),
         {:ok, batch_count, condition} <- read_batch_count(config, id) do
      append_batch(config, id, batch_count, condition, detach_completion_values(events))
    end
  end

  # Non-durable Turns share the Runner Store but do not persist execution events.
  def append(_id, _events, _jido), do: {:ok, 0}

  @impl true
  def stream(id, {id, jido}), do: stream(id, jido)

  def stream({:jido_execution, _, _, _, _} = id, jido) do
    with {:ok, config} <- config(jido, id),
         {:ok, events} <- read_events(config, id, :repair) do
      restore_completion_values(events, FactResolver.new({__MODULE__, {id, config}}))
    end
  end

  def stream(_id, _jido), do: {:error, :not_found}

  defp read_events(config, id, mode) do
    with {:ok, batch_count, _condition} <- read_batch_count(config, id, mode),
         true <- batch_count > 0,
         {:ok, batches} <- read_batches(config, id, 1, batch_count, []) do
      batches
      |> Enum.reverse()
      |> Enum.concat()
      |> reference_join_values()
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def save_fact({:jido_execution, _, _, _, _} = id, hash, value, jido) do
    with {:ok, config} <- config(jido, id) do
      save_fact_value(config, id, hash, value)
    end
  end

  def save_fact(_id, _hash, _value, _jido), do: :ok

  def load_fact({:jido_execution, _, _, _, _} = id, hash, jido) do
    with {:ok, config} <- config(jido, id), do: read_fact(config, id, hash)
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

  defp reference_join_values(events),
    do:
      {:ok,
       Enum.map(events, fn
         %Runic.Workflow.Events.JoinCompleted{result_value: nil} = event ->
           JoinCompletedRef.from_event(event)

         event ->
           event
       end)}

  # Runic persists FactProduced values before it appends a batch with their
  # values cleared. A matching completion can use the same saved value.
  defp detach_completion_values(events) do
    saved =
      for %FactProduced{value: nil, hash: hash, payload_digest: %Runic.Identity{} = digest} <- events,
          into: MapSet.new(),
          do: {hash, digest}

    Enum.map(events, fn
      %RunnableCompleted{result_fact: %Fact{} = fact} = event ->
        if MapSet.member?(saved, {fact.hash, fact.payload_digest}) do
          %{event | result_fact: struct!(FactRef, Map.drop(Map.from_struct(fact), [:value]))}
        else
          event
        end

      event ->
        event
    end)
  end

  defp restore_completion_values(events, resolver) do
    events
    |> Enum.reduce_while([], fn
      %RunnableCompleted{result_fact: %FactRef{} = ref} = event, restored ->
        case FactResolver.resolve(ref, resolver) do
          {:ok, fact} -> {:cont, [%{event | result_fact: fact} | restored]}
          {:error, _reason} -> {:halt, {:error, :invalid_execution_checkpoint}}
        end

      event, restored ->
        {:cont, [event | restored]}
    end)
    |> case do
      {:error, _reason} = error -> error
      restored -> {:ok, Enum.reverse(restored)}
    end
  end

  def read_workflow(%Config{} = profile, id), do: load_workflow(profile, id, :read)

  def update_workflow(jido, id, transition) do
    with {:ok, profile} <- config(jido, id),
         {:ok, workflow} <- load_workflow(profile, id, :repair) do
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
    else
      {:error, :not_found} -> {:ok, nil}
      error -> error
    end
  end

  defp load_workflow(profile, id, mode) do
    with {:ok, events} <- read_events(profile, id, mode),
         do: rehydrate_frontier(events, id, profile)
  end

  defp rehydrate_frontier(events, id, profile) do
    workflow = Runic.Workflow.from_events(events, nil, fact_mode: :ref)

    required = Rehydration.classify(workflow).hot

    resolver = FactResolver.new({__MODULE__, {id, profile}})
    {workflow, resolver} = Rehydration.resolve_hot(workflow, required, resolver)
    wait_inputs = wait_input_hashes(workflow)
    required = MapSet.union(required, wait_inputs)
    {workflow, _resolver} = Rehydration.resolve_hot(workflow, wait_inputs, resolver)

    if Enum.all?(required, &match?(%Fact{}, Map.get(workflow.graph.vertices, &1))) do
      {:ok, Runic.Workflow.enable_event_emission(workflow)}
    else
      {:error, :invalid_execution_checkpoint}
    end
  end

  defp wait_input_hashes(workflow) do
    pending_ids = workflow |> Runtime.pending_waits() |> MapSet.new(& &1.id)

    for %Fact{
          meta: %{jido_wait_record: true},
          value: %{type: :jido_wait_request, id: id, input_id: input_id}
        } <- Runic.Workflow.facts(workflow),
        MapSet.member?(pending_ids, id),
        into: MapSet.new(),
        do: input_id
  end

  defp persist_events(id, events, jido) do
    with :ok <- persist_event_facts(events, id, jido) do
      append(id, strip_event_fact_values(events), jido)
    end
  end

  defp persist_event_facts(events, id, jido) do
    Enum.reduce_while(events, :ok, fn
      %FactProduced{} = event, :ok ->
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
      %FactProduced{} = event -> %{event | value: nil}
      event -> event
    end)
  end

  defp config(jido, id) do
    case Jido.Instance.RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, config}} ->
        if Process.alive?(owner), do: {:ok, config}, else: {:error, :execution_owner_lost}

      _ ->
        {:error, :execution_store_unavailable}
    end
  end

  defp append_batch(_config, _id, batch_count, _condition, []), do: {:ok, batch_count}

  defp append_batch(config, id, batch_count, condition, events) do
    next = batch_count + 1

    with {:ok, bytes} <- encode_payload(config, events),
         :ok <-
           Store.compare_and_swap(
             config.store,
             batch_key(id, next),
             :not_found,
             bytes
           ),
         :ok <- write_batch_count(config, id, condition, next) do
      {:ok, next}
    end
  end

  defp save_fact_value(config, id, hash, value) do
    case Store.read(config.store, fact_key(id, hash)) do
      {:ok, _bytes, _condition} ->
        accept_existing_fact(config, id, hash, value)

      {:error, :not_found} ->
        with :ok <- record_fact_hash(config, id, hash),
             {:ok, bytes} <- encode_payload(config, full_fact_record(value)) do
          case Store.compare_and_swap(
                 config.store,
                 fact_key(id, hash),
                 :not_found,
                 bytes
               ) do
            :ok -> :ok
            {:error, :conflict} -> accept_existing_fact(config, id, hash, value)
            error -> error
          end
        end

      error ->
        error
    end
  end

  defp accept_existing_fact(config, id, hash, value) do
    with {:ok, stored} <- load_fact_value(config, id, hash),
         true <- stored === value do
      record_fact_hash(config, id, hash)
    else
      false -> {:error, :fact_value_conflict}
      error -> error
    end
  end

  defp full_fact_record(value),
    do: {@fact_tag, @fact_version, 0, fact_digest(value), :full, value}

  defp load_fact_value(config, id, hash) do
    with {:ok, bytes, _condition} <- Store.read(config.store, fact_key(id, hash)),
         {:ok, record} <- decode(config, bytes) do
      decode_fact_record(record)
    end
  end

  defp decode_fact_record({@fact_tag, @fact_version, 0, digest, :full, value})
       when is_binary(digest) and byte_size(digest) == 32 do
    with :ok <- verify_fact_digest(value, digest), do: {:ok, value}
  end

  defp decode_fact_record(_record), do: {:error, :invalid_execution_checkpoint}

  defp accept_prepared(config, id, expected) do
    with {:ok, bytes, _condition} <- Store.read(config.store, prepared_key(id)),
         {:ok, actual} <- decode(config, bytes) do
      if actual == expected, do: :ok, else: {:error, :execution_prepare_conflict}
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
        with {:ok, bytes} <- Config.encode(config, {:jido_fact_index, 1, [hash | hashes]}) do
          case Store.compare_and_swap(
                 config.store,
                 fact_index_key(id),
                 condition,
                 bytes
               ) do
            :ok -> :ok
            {:error, :conflict} -> record_fact_hash(config, id, hash, attempts - 1)
            error -> error
          end
        end
      end
    end
  end

  defp read_fact_index(config, id) do
    case Store.read(config.store, fact_index_key(id)) do
      {:ok, bytes, condition} ->
        case decode(config, bytes) do
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

  defp read_batch_count(config, id, mode \\ :repair) do
    case Store.read(config.store, key(id)) do
      {:ok, bytes, condition} ->
        with {:ok, batch_count} when is_integer(batch_count) and batch_count >= 0 <-
               decode(config, bytes) do
          recover_tail(config, id, batch_count, condition, mode)
        else
          _invalid -> {:error, :invalid_execution_checkpoint}
        end

      {:error, :not_found} ->
        recover_tail(config, id, 0, :not_found, mode)

      error ->
        error
    end
  end

  # The batch is the commit. Read-only projections follow committed batches
  # beyond the count without repairing that count.
  defp recover_tail(config, id, batch_count, condition, mode) do
    next = batch_count + 1

    case Store.read(config.store, batch_key(id, next)) do
      {:ok, bytes, _chunk_condition} ->
        with {:ok, _events} <- decode_batch(config, bytes) do
          case mode do
            :read ->
              recover_tail(config, id, next, condition, mode)

            :repair ->
              with :ok <- write_batch_count(config, id, condition, next),
                   do: read_batch_count(config, id, mode)
          end
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
    with {:ok, bytes, _condition} <- Store.read(config.store, batch_key(id, index)),
         {:ok, events} <- decode_batch(config, bytes) do
      read_batches(config, id, index + 1, last, [events | batches])
    end
  end

  defp decode_batch(config, bytes) do
    with {:ok, [_ | _] = events} <- decode(config, bytes),
         false <- List.improper?(events) do
      {:ok, events}
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp write_batch_count(config, id, condition, batch_count) do
    with {:ok, bytes} <- Config.encode(config, batch_count) do
      Store.compare_and_swap(config.store, key(id), condition, bytes)
    end
  end

  defp encode_payload(%Config{codec: Term, execution_compression: true}, value),
    do: Term.encode_compact(value)

  defp encode_payload(config, value), do: Config.encode(config, value)

  # Runic events contain domain atoms and code references. These are trusted
  # runtime records, not ingress payloads, so :safe cannot decode them.
  defp decode(config, bytes) when is_binary(bytes) do
    case Config.decode(config, bytes, trusted: true) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp delete_execution(config, id) do
    with {:ok, batch_count, _condition} <- read_batch_count(config, id),
         {:ok, indexed_hashes, _condition} <- read_fact_index(config, id) do
      batch_keys = for index <- batch_count..1//-1, batch_count > 0, do: batch_key(id, index)
      fact_keys = for hash <- Enum.uniq(indexed_hashes), do: fact_key(id, hash)

      Enum.each(
        [key(id), prepared_key(id), fact_index_key(id) | batch_keys ++ fact_keys],
        &delete_record(config, &1)
      )
    end
  end

  defp delete_record(config, key), do: Store.delete(config.store, key)

  defp key(id), do: @prefix <> Base.url_encode64(:erlang.term_to_binary(id), padding: false)

  defp batch_key(id, index), do: key(id) <> ":batches:" <> Integer.to_string(index)
  defp prepared_key(id), do: key(id) <> ":prepared"
  defp fact_index_key(id), do: key(id) <> ":facts:index"

  defp fact_key(id, hash) do
    key(id) <>
      ":facts:" <>
      Base.url_encode64(:erlang.term_to_binary(hash, [:deterministic]), padding: false)
  end

  defp fact_digest(value), do: :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))

  defp verify_fact_digest(value, digest) do
    if fact_digest(value) == digest, do: :ok, else: {:error, :invalid_execution_checkpoint}
  end
end
