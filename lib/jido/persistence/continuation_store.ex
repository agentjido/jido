defmodule Jido.Persistence.ContinuationStore do
  @moduledoc false
  @behaviour Runic.Runner.Store

  alias Jido.Persistence.{Config, Store}
  alias Jido.Persistence.Codec.Term
  alias Jido.Exec.Runtime
  alias __MODULE__.{BinaryDictionary, JoinCompletedRef, SharedToolPayload, ToolPayload, ToolReceipt}
  alias Jido.Instance.RuntimeStore
  alias Runic.Identity
  alias Runic.Workflow.{Fact, FactRef, FactResolver, Rehydration, RunnableCompleted, RunnableDispatched}
  alias Runic.Workflow.Events.{FactProduced, JoinCompleted}

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
      case RuntimeStore.fetch(jido, __MODULE__, id) do
        {:ok, {^owner, %{config: ^profile}}} ->
          :ok

        _unregistered ->
          with {:ok, hashes, _condition} <- read_fact_index(profile, id),
               {:ok, catalogue} <- restore_tool_catalogue(profile, id, hashes),
               {:ok, catalogue} <- restore_prepared_catalogue(profile, id, catalogue) do
            entry = %{config: profile, catalogue: catalogue, facts: Map.from_keys(hashes, :indexed)}
            RuntimeStore.put(jido, __MODULE__, id, {owner, entry})
          end
      end
    end
  end

  def tool_recorder(jido, id) do
    fn slot, call, execute -> record_tool(jido, id, slot, fact_digest(call), execute) end
  end

  defp record_tool(jido, id, slot, signature, execute) do
    with {:ok, owner, %{config: profile}} <- registration(jido, id),
         {:ok, result, receipt, payloads} <- fetch_or_record_tool(profile, id, slot, signature, execute),
         :ok <- update_tool_catalogue(jido, id, owner, &ToolReceipt.add_payloads(receipt, &1, slot, payloads)) do
      {:ok, result}
    end
  end

  defp update_tool_catalogue(jido, id, owner, update) do
    update_registration(jido, id, owner, &Map.update!(&1, :catalogue, update))
  end

  defp update_registration(jido, id, owner, update) do
    case registration(jido, id) do
      {:ok, ^owner, current} ->
        next = update.(current)

        if next == current do
          :ok
        else
          case RuntimeStore.compare_and_swap_owned(
                 jido,
                 __MODULE__,
                 id,
                 owner,
                 current,
                 next
               ) do
            {:error, :conflict} -> update_registration(jido, id, owner, update)
            result -> result
          end
        end

      {:ok, _replaced, _entry} ->
        {:error, :execution_owner_replaced}

      error ->
        error
    end
  end

  defp fetch_or_record_tool(profile, id, slot, signature, execute) do
    case read_tool_receipt(profile, id, slot) do
      {:ok, receipt} -> ToolReceipt.result(profile, id, receipt, signature)
      {:error, :not_found} -> save_tool_receipt(profile, id, slot, signature, execute.())
      error -> error
    end
  end

  defp save_tool_receipt(profile, id, slot, signature, result) do
    hash = tool_hash(slot)
    key = fact_key(id, hash)

    with {:ok, receipt, payloads} <- ToolReceipt.build(profile, signature, result),
         {:ok, bytes} <- encode_payload(profile, receipt),
         :ok <- record_fact_hash(profile, id, hash) do
      case Store.compare_and_swap(profile.store, key, :not_found, bytes) do
        :ok ->
          {:ok, result, receipt, payloads}

        {:error, :conflict} ->
          with {:ok, receipt} <- read_tool_receipt(profile, id, slot),
               do: ToolReceipt.result(profile, id, receipt, signature)

        error ->
          error
      end
    end
  end

  defp read_tool_receipt(profile, id, slot, opts \\ [trusted: true]),
    do: ToolReceipt.read(profile, fact_key(id, tool_hash(slot)), opts)

  defp restore_tool_catalogue(profile, id, hashes) do
    Enum.reduce_while(hashes, {:ok, ToolPayload.new()}, fn
      {:jido_tool_result, slot}, {:ok, catalogue} ->
        case read_tool_receipt(profile, id, slot) do
          {:ok, receipt} ->
            case ToolReceipt.payloads(profile, id, receipt) do
              {:ok, payloads} -> {:cont, {:ok, ToolReceipt.add_payloads(receipt, catalogue, slot, payloads)}}
              {:error, _reason} = error -> {:halt, error}
            end

          {:error, :not_found} ->
            # The index is saved before its receipt. An interrupted save can leave an empty slot.
            {:cont, {:ok, catalogue}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      _fact_hash, result ->
        {:cont, result}
    end)
  end

  defp tool_hash(slot), do: {:jido_tool_result, slot}

  def prepare(jido, id, value) do
    with {:ok, owner, %{config: config, catalogue: catalogue}} <- registration(jido, id),
         record = {:jido_execution_prepared, 3, value},
         {:ok, bytes} <- encode_referenced(config, record, ToolPayload.without_source(catalogue, :prepared)),
         :ok <- save_prepared(config, id, record, bytes) do
      payloads = prepared_payloads(config, value)
      update_tool_catalogue(jido, id, owner, &ToolPayload.add(&1, :prepared, payloads))
    end
  end

  defp save_prepared(config, id, record, bytes) do
    case Store.compare_and_swap(config.store, prepared_key(id), :not_found, bytes) do
      :ok -> :ok
      {:error, :conflict} -> accept_prepared(config, id, record)
      {:error, _reason} = error -> error
    end
  end

  defp restore_prepared_catalogue(%Config{codec: Term} = config, id, catalogue) do
    case read_prepared(config, id, trusted: true) do
      {:ok, {:jido_execution_prepared, 3, value}} ->
        {:ok, ToolPayload.add(catalogue, :prepared, prepared_payloads(config, value))}

      {:error, :not_found} ->
        {:ok, catalogue}

      {:error, _reason} = error ->
        error
    end
  end

  defp restore_prepared_catalogue(_config, _id, catalogue), do: {:ok, catalogue}

  defp prepared_payloads(%Config{codec: Term}, %{signal: %Jido.Signal{type: "jido.ai.request"}} = value) do
    payloads =
      [:signal, :admitted_signal]
      |> Enum.reduce(%{}, fn key, acc ->
        case Map.get(value, key) do
          %Jido.Signal{data: %{input: input}} -> ToolPayload.payloads(input, acc)
          %Jido.Signal{data: %{"input" => input}} -> ToolPayload.payloads(input, acc)
          _other -> acc
        end
      end)

    context = Map.get(value, :context, %{})

    context
    |> session_sources()
    |> Enum.reduce(payloads, &session_payloads/2)
  end

  defp prepared_payloads(_config, _value), do: %{}

  defp session_sources(%{agent_state: %{session: session}} = context),
    do: [session, Map.get(context, :jido_ai_session)]

  defp session_sources(context), do: [Map.get(context, :jido_ai_session)]

  defp session_payloads(value, payloads) do
    case Jido.Session.decode(value) do
      {:ok, session} -> Enum.reduce(session.thread.entries, payloads, &entry_payloads/2)
      {:error, _reason} -> payloads
    end
  end

  defp entry_payloads(%{kind: :ai_message, payload: %{"role" => role, "content" => content}}, payloads)
       when role in ["user", "assistant"],
       do: ToolPayload.payloads(content, payloads)

  defp entry_payloads(%{kind: :ai_message, payload: %{"role" => "tool"} = tool}, payloads),
    do: ToolPayload.payloads(tool, payloads)

  defp entry_payloads(%{kind: :ai_tool_attempt, payload: tool}, payloads), do: ToolPayload.payloads(tool, payloads)
  defp entry_payloads(_entry, payloads), do: payloads

  # Terminal checkpoint collection is best effort. A failed physical delete
  # must not change a Turn result which is already durable in the Agent record.
  def collect(jido, id) do
    case RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, %{config: config}}} when owner == self() ->
        with :ok <- RuntimeStore.delete_owned(jido, __MODULE__, id, owner),
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
         {:ok, _owner, %{config: config, catalogue: catalogue, facts: facts}} <- registration(jido, id),
         {:ok, events} <- detach_dispatch_values(events, config, id, facts),
         {:ok, batch_count, condition} <- read_batch_count(config, id) do
      append_batch(config, id, batch_count, condition, detach_completion_values(events), catalogue)
    end
  end

  # Non-durable Turns share the Runner Store but do not persist execution events.
  def append(_id, _events, _jido), do: {:ok, 0}

  @impl true
  def stream(id, {id, jido}), do: stream(id, jido)

  def stream({:jido_execution, _, _, _, _} = id, jido) do
    with {:ok, config} <- config(jido, id),
         {:ok, events} <- read_events(config, id, :repair) do
      restore_lifecycle_values(events, FactResolver.new({__MODULE__, {id, config}}))
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

  def save_fact({:jido_execution, _, _, _, _} = id, hash, value, jido),
    do: save_fact(id, hash, value, jido, nil)

  def save_fact(_id, _hash, _value, _jido), do: :ok

  defp save_fact(id, hash, value, jido, contributions) do
    digest = fact_digest(value)

    with {:ok, owner, entry} <- registration(jido, id),
         :ok <- save_fact_value(entry, id, hash, value, digest, contributions) do
      update_registration(jido, id, owner, fn entry -> %{entry | facts: Map.put(entry.facts, hash, digest)} end)
    end
  end

  def load_fact({:jido_execution, _, _, _, _} = id, hash, jido) do
    with {:ok, config} <- config(jido, id), do: read_fact(config, id, hash)
  end

  def load_fact(_id, _hash, _jido), do: {:error, :not_found}

  defp detach_join_values(events, id, jido) do
    Enum.reduce_while(events, {:ok, []}, fn
      %JoinCompleted{} = event, {:ok, detached} ->
        case save_fact(id, event.result_fact_hash, event.result_value, jido, event.contribution_fact_hashes) do
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
         %JoinCompleted{result_value: nil} = event ->
           JoinCompletedRef.from_event(event)

         event ->
           event
       end)}

  defp detach_dispatch_values(events, config, id, facts) do
    events
    |> Enum.reduce_while([], fn
      %RunnableDispatched{input_fact: %Fact{hash: hash, value: value} = fact} = event, detached ->
        case confirmed_fact?(Map.get(facts, hash), config, id, hash, value) do
          {:ok, true} -> {:cont, [%{event | input_fact: fact_ref(fact)} | detached]}
          {:ok, false} -> {:cont, [event | detached]}
          {:error, _reason} = error -> {:halt, error}
        end

      event, detached ->
        {:cont, [event | detached]}
    end)
    |> case do
      {:error, _reason} = error -> error
      detached -> {:ok, Enum.reverse(detached)}
    end
  end

  # An index entry is reserved before its value is written. After a restart,
  # check the row itself before using the index entry as a reference source.
  defp confirmed_fact?(:indexed, config, id, hash, value) do
    case load_fact_value(config, id, hash) do
      {:ok, stored} -> {:ok, stored === value}
      {:error, :not_found} -> {:ok, false}
      error -> error
    end
  end

  defp confirmed_fact?(digest, _config, _id, _hash, value) when is_binary(digest),
    do: {:ok, fact_digest(value) == digest}

  defp confirmed_fact?(nil, _config, _id, _hash, _value), do: {:ok, false}

  defp fact_ref(fact), do: struct!(FactRef, Map.drop(Map.from_struct(fact), [:value]))

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
          %{event | result_fact: fact_ref(fact)}
        else
          event
        end

      event ->
        event
    end)
  end

  defp restore_lifecycle_values(events, resolver) do
    events
    |> Enum.reduce_while({[], resolver}, fn event, {restored, resolver} ->
      case lifecycle_ref(event) do
        {field, ref} ->
          resolver = FactResolver.preload(resolver, [ref.hash])

          case FactResolver.resolve(ref, resolver) do
            {:ok, fact} -> {:cont, {[Map.replace!(event, field, fact) | restored], resolver}}
            {:error, _reason} -> {:halt, {:error, :invalid_execution_checkpoint}}
          end

        nil ->
          {:cont, {[event | restored], resolver}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      {restored, _resolver} -> {:ok, Enum.reverse(restored)}
    end
  end

  defp lifecycle_ref(%RunnableDispatched{input_fact: %FactRef{} = ref}), do: {:input_fact, ref}
  defp lifecycle_ref(%RunnableCompleted{result_fact: %FactRef{} = ref}), do: {:result_fact, ref}
  defp lifecycle_ref(_event), do: nil

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
    with {:ok, _owner, %{config: config}} <- registration(jido, id), do: {:ok, config}
  end

  defp registration(jido, id) do
    case RuntimeStore.fetch(jido, __MODULE__, id) do
      {:ok, {owner, entry}} ->
        if Process.alive?(owner), do: {:ok, owner, entry}, else: {:error, :execution_owner_lost}

      _ ->
        {:error, :execution_store_unavailable}
    end
  end

  defp append_batch(_config, _id, batch_count, _condition, [], _catalogue), do: {:ok, batch_count}

  defp append_batch(config, id, batch_count, condition, events, catalogue) do
    next = batch_count + 1

    with {:ok, bytes} <- encode_batch(config, events, catalogue),
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

  defp save_fact_value(%{config: config, catalogue: catalogue, facts: facts}, id, hash, value, digest, contributions) do
    case Store.read(config.store, fact_key(id, hash)) do
      {:ok, _bytes, _condition} ->
        accept_existing_fact(config, id, hash, value)

      {:error, :not_found} ->
        with {:ok, format, contents} <- fact_contents(contributions, value, hash, config, id, facts),
             :ok <- record_fact_hash(config, id, hash),
             record = {@fact_tag, @fact_version, 0, digest, format, contents},
             {:ok, bytes} <- encode_fact(config, record, catalogue) do
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

  # A Join result is the ordered list of its input values. Use a recipe only
  # when every input already has an exact, smaller reference in this execution.
  defp fact_contents([_ | _] = hashes, value, hash, config, id, facts) do
    with {:ok, confirmed?} <- confirmed_contributions?(hashes, value, hash, config, id, facts) do
      if confirmed? and :erlang.external_size(hashes) < :erlang.external_size(value),
        do: {:ok, :join, hashes},
        else: {:ok, :full, value}
    end
  end

  defp fact_contents(_contributions, value, _hash, _config, _id, _facts), do: {:ok, :full, value}

  defp confirmed_contributions?([input | hashes], [value | values], hash, config, id, facts) when input !== hash do
    case confirmed_fact?(Map.get(facts, input), config, id, input, value) do
      {:ok, true} -> confirmed_contributions?(hashes, values, hash, config, id, facts)
      other -> other
    end
  end

  defp confirmed_contributions?([], [], _hash, _config, _id, _facts), do: {:ok, true}
  defp confirmed_contributions?(_hashes, _values, _hash, _config, _id, _facts), do: {:ok, false}

  defp accept_existing_fact(config, id, hash, value) do
    with {:ok, stored} <- load_fact_value(config, id, hash),
         true <- stored === value do
      record_fact_hash(config, id, hash)
    else
      false -> {:error, :fact_value_conflict}
      error -> error
    end
  end

  defp load_fact_value(config, id, hash) do
    with {:ok, value, _known} <- resolve_fact(config, id, fact_key(id, hash), %{}, trusted: true),
         do: {:ok, value}
  end

  # Cache resolved values for one reconstruction. The in-progress entry
  # rejects cycles and distinguishes them from a valid nil contribution.
  defp resolve_fact(config, id, key, known, opts) do
    case Map.fetch(known, key) do
      {:ok, :loading} ->
        {:error, :invalid_execution_checkpoint}

      {:ok, {:loaded, value}} ->
        {:ok, value, known}

      :error ->
        with {:ok, bytes, _condition} <- Store.read(config.store, key),
             {:ok, record} <- decode_referenced(config, id, bytes, opts) do
          resolve_fact_record(record, config, id, key, known, opts)
        end
    end
  end

  defp resolve_fact_record({@fact_tag, @fact_version, 0, digest, format, contents}, config, id, key, known, opts)
       when is_binary(digest) and byte_size(digest) == 32 do
    loading = Map.put(known, key, :loading)

    with {:ok, value, known} <- resolve_fact_contents(format, contents, config, id, loading, opts),
         :ok <- verify_fact_digest(value, digest) do
      {:ok, value, Map.put(known, key, {:loaded, value})}
    end
  end

  defp resolve_fact_record(_record, _config, _id, _key, _known, _opts), do: {:error, :invalid_execution_checkpoint}

  defp resolve_fact_contents(:full, value, _config, _id, known, _opts), do: {:ok, value, known}

  defp resolve_fact_contents(:join, [_ | _] = hashes, config, id, known, opts) do
    if List.improper?(hashes) do
      {:error, :invalid_execution_checkpoint}
    else
      hashes
      |> Enum.reduce_while({:ok, [], known}, fn hash, {:ok, values, seen} ->
        case resolve_fact(config, id, fact_key(id, hash), seen, opts) do
          {:ok, value, seen} -> {:cont, {:ok, [value | values], seen}}
          {:error, _reason} -> {:halt, {:error, :invalid_execution_checkpoint}}
        end
      end)
      |> case do
        {:ok, values, seen} -> {:ok, Enum.reverse(values), seen}
        error -> error
      end
    end
  end

  defp resolve_fact_contents(_format, _contents, _config, _id, _known, _opts),
    do: {:error, :invalid_execution_checkpoint}

  defp accept_prepared(config, id, expected) do
    with {:ok, actual} <- read_prepared(config, id, trusted: true) do
      if actual == expected, do: :ok, else: {:error, :execution_prepare_conflict}
    end
  end

  defp read_prepared(config, id, opts) do
    with {:ok, bytes, _condition} <- Store.read(config.store, prepared_key(id)) do
      # A preparation can reference shared tool payloads. It cannot reference itself.
      with {:ok, encoded} <- Config.decode(config, bytes, opts),
           {:ok, {:jido_execution_prepared, 3, value} = record} <-
             expand_payloads(config, id, encoded, Keyword.put(opts, :allow_prepared, false)),
           true <- is_map(value) do
        {:ok, record}
      else
        _invalid -> {:error, :invalid_execution_checkpoint}
      end
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
        with {:ok, bytes} <- Config.encode(config, encode_fact_index([hash | hashes])) do
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
        with {:ok, record} <- decode(config, bytes),
             {:ok, hashes} <- decode_fact_index(record) do
          {:ok, hashes, condition}
        end

      {:error, :not_found} ->
        {:ok, [], :not_found}

      error ->
        error
    end
  end

  defp encode_fact_index(hashes), do: {:jido_fact_index, 2, Enum.map(hashes, &encode_fact_hash/1)}

  defp encode_fact_hash(%Identity{scheme: :sha256, version: 1, domain: :fact_occurrence, digest: digest})
       when is_binary(digest) and byte_size(digest) == 32,
       do: digest

  defp encode_fact_hash(hash), do: {:opaque, hash}

  defp decode_fact_index({:jido_fact_index, 1, hashes}) when is_list(hashes) do
    if List.improper?(hashes), do: {:error, :invalid_execution_checkpoint}, else: {:ok, hashes}
  end

  defp decode_fact_index({:jido_fact_index, 2, entries}), do: decode_fact_hashes(entries, [])
  defp decode_fact_index(_record), do: {:error, :invalid_execution_checkpoint}

  defp decode_fact_hashes([], reversed), do: {:ok, Enum.reverse(reversed)}

  defp decode_fact_hashes([digest | rest], reversed) when is_binary(digest) and byte_size(digest) == 32 do
    hash = %Identity{scheme: :sha256, version: 1, domain: :fact_occurrence, digest: digest}
    decode_fact_hashes(rest, [hash | reversed])
  end

  defp decode_fact_hashes([{:opaque, hash} | rest], reversed), do: decode_fact_hashes(rest, [hash | reversed])
  defp decode_fact_hashes(_entries, _reversed), do: {:error, :invalid_execution_checkpoint}

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
        with {:ok, _events} <- decode_batch(config, id, bytes) do
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
         {:ok, events} <- decode_batch(config, id, bytes) do
      read_batches(config, id, index + 1, last, [events | batches])
    end
  end

  defp decode_batch(config, id, bytes) do
    with {:ok, [_ | _] = events} <- decode_referenced(config, id, bytes),
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

  defp encode_batch(%Config{codec: Term, execution_compression: false} = config, events, catalogue) do
    with {:ok, bytes} <- encode_referenced(config, events, catalogue) do
      BinaryDictionary.encode(bytes, BinaryDictionary.identity_patterns(events))
    end
  end

  defp encode_batch(config, events, catalogue), do: encode_referenced(config, events, catalogue)

  defp encode_fact(
         %Config{codec: Term, execution_compression: false} = config,
         {@fact_tag, @fact_version, 0, _digest, :full, value} = record,
         catalogue
       ) do
    with {:ok, bytes} <- encode_referenced(config, record, catalogue) do
      payloads = value |> ToolPayload.payloads() |> Map.values()
      patterns = Enum.uniq(payloads ++ BinaryDictionary.identity_patterns(value))
      BinaryDictionary.encode(bytes, patterns)
    end
  end

  defp encode_fact(config, record, catalogue), do: encode_referenced(config, record, catalogue)

  defp encode_payload(%Config{codec: Term, execution_compression: true}, value),
    do: Term.encode_compact(value)

  defp encode_payload(config, value), do: Config.encode(config, value)

  defp encode_referenced(%Config{codec: Term} = config, value, {_refs, pattern} = catalogue)
       when not is_nil(pattern) do
    with {:ok, bytes} <- Config.encode(config, value) do
      case ToolPayload.pack(bytes, catalogue) do
        ^bytes when not config.execution_compression -> {:ok, bytes}
        ^bytes -> encode_payload(config, value)
        packed -> encode_payload(config, packed)
      end
    end
  end

  defp encode_referenced(config, value, _catalogue), do: encode_payload(config, value)

  def inspect_record(config, @prefix <> suffix, {:jido_execution_dictionary, 1, _, _} = record),
    do: inspect_referenced_record(config, suffix, record)

  def inspect_record(config, @prefix <> suffix, {:jido_tool_payload_refs, 1, _segments} = packed),
    do: inspect_referenced_record(config, suffix, packed)

  def inspect_record(config, @prefix <> suffix, {@fact_tag, @fact_version, 0, _, :join, _} = record),
    do: inspect_referenced_record(config, suffix, record)

  def inspect_record(_config, _key, {:jido_fact_index, _version, _entries} = record) do
    with {:ok, hashes} <- decode_fact_index(record), do: {:ok, {:jido_fact_index, 1, hashes}}
  end

  def inspect_record(_config, _key, record), do: {:ok, record}

  defp inspect_referenced_record(config, suffix, record) do
    [encoded_id | record_key] = String.split(suffix, ":", parts: 2)

    with {:ok, bytes} <- Base.url_decode64(encoded_id, padding: false),
         {:ok, id} <- decode_identity(bytes),
         {:ok, record} <- expand_dictionary(config, record, []),
         {:ok, record} <- expand_payloads(config, id, record, allow_prepared: record_key != ["prepared"]) do
      inspect_join_fact(config, id, @prefix <> suffix, record)
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp inspect_join_fact(config, id, key, {@fact_tag, @fact_version, 0, digest, :join, _} = record) do
    with {:ok, value, _known} <- resolve_fact_record(record, config, id, key, %{}, []),
         do: {:ok, {@fact_tag, @fact_version, 0, digest, :full, value}}
  end

  defp inspect_join_fact(_config, _id, _key, record), do: {:ok, record}

  defp decode_identity(bytes) do
    case :erlang.binary_to_term(bytes, [:safe]) do
      {:jido_execution, namespace, partition, agent_id, turn_id} = id
      when is_binary(namespace) and (is_binary(partition) or is_nil(partition)) and is_binary(agent_id) and
             is_binary(turn_id) ->
        {:ok, id}

      _invalid ->
        :error
    end
  rescue
    ArgumentError -> :error
  end

  defp decode_referenced(config, id, bytes, opts \\ [trusted: true]) do
    with {:ok, record} <- decode(config, bytes, opts),
         {:ok, record} <- expand_dictionary(config, record, opts) do
      expand_payloads(config, id, record, opts)
    end
  end

  defp expand_dictionary(config, {:jido_execution_dictionary, 1, _, _} = record, opts) do
    with {:ok, bytes} <- BinaryDictionary.unpack(record), do: decode(config, bytes, opts)
  end

  defp expand_dictionary(_config, record, _opts), do: {:ok, record}

  defp expand_payloads(config, id, {:jido_tool_payload_refs, 1, _} = packed, opts) do
    with {:ok, plain} <- ToolPayload.unpack(packed, &load_tool_payloads(config, id, &1, opts)),
         {:ok, record} <- Config.decode(config, plain, opts) do
      {:ok, record}
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp expand_payloads(_config, _id, record, _opts), do: {:ok, record}

  defp load_tool_payloads(config, id, :prepared, opts) do
    with true <- Keyword.get(opts, :allow_prepared, true),
         {:ok, {:jido_execution_prepared, 3, value}} <- read_prepared(config, id, opts) do
      {:ok, prepared_payloads(config, value)}
    else
      _invalid -> {:error, :invalid_execution_checkpoint}
    end
  end

  defp load_tool_payloads(config, id, {:shared, digest}, _opts)
       when is_binary(digest) and byte_size(digest) == 32 do
    with {:ok, bytes} <- SharedToolPayload.read(config, id, digest), do: {:ok, %{digest => bytes}}
  end

  defp load_tool_payloads(config, id, slot, opts) do
    with {:ok, receipt} <- read_tool_receipt(config, id, slot, opts), do: ToolReceipt.payloads(config, id, receipt)
  end

  # Runic events contain domain atoms and code references. These are trusted
  # runtime records, not ingress payloads, so :safe cannot decode them.
  defp decode(config, bytes, opts \\ [trusted: true]) when is_binary(bytes) do
    case Config.decode(config, bytes, opts) do
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
