defmodule Jido.Bus.Adapters.InMemory do
  @moduledoc """
  An in-memory signal store adapter implemented as a `GenServer` process which
  stores signals in memory only.

  This is only designed for testing purposes.
  """

  @behaviour Jido.Bus.Adapter

  use GenServer

  defmodule State do
    @moduledoc false

    defstruct [
      :name,
      :serializer,
      persisted_signals: [],
      streams: %{},
      transient_subscribers: %{},
      persistent_subscriptions: %{},
      snapshots: %{},
      next_signal_number: 1
    ]
  end

  alias Jido.Bus.Adapters.InMemory.{PersistentSubscription, State, Subscription}
  alias Jido.Bus.{RecordedSignal, Snapshot}
  alias Jido.Signal

  def start_link(opts \\ []) do
    {start_opts, in_memory_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    state = %State{
      name: Keyword.fetch!(opts, :name),
      serializer: Keyword.get(in_memory_opts, :serializer)
    }

    GenServer.start_link(__MODULE__, state, start_opts)
  end

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state}
  end

  @impl Jido.Bus.Adapter
  def child_spec(application, config) do
    {bus_name, config} = parse_config(application, config)

    supervisor_name = Module.concat([bus_name, "SubscriptionsSupervisor"])
    adapter_name = Module.concat([bus_name, "Bus"])

    child_spec = [
      {DynamicSupervisor, strategy: :one_for_one, name: supervisor_name},
      %{
        id: adapter_name,
        start: {__MODULE__, :start_link, [config]}
      }
    ]

    {:ok, child_spec, %{name: bus_name}}
  end

  @impl Jido.Bus.Adapter
  def publish(bus, stream_id, expected_version, signals, _opts \\ []) do
    bus = bus_name(bus)

    GenServer.call(bus, {:append, stream_id, expected_version, signals})
  end

  @impl Jido.Bus.Adapter
  def replay(bus, stream_id, start_version \\ 0, read_batch_size \\ 1_000)

  def replay(bus, stream_id, start_version, _read_batch_size) do
    bus = bus_name(bus)

    GenServer.call(bus, {:replay, stream_id, start_version})
  end

  @impl Jido.Bus.Adapter
  def subscribe(bus, stream_id) do
    bus = bus_name(bus)

    GenServer.call(bus, {:subscribe, stream_id, self()})
  end

  @impl Jido.Bus.Adapter
  def subscribe_persistent(
        bus,
        stream_id,
        subscription_name,
        subscriber,
        start_from,
        opts
      ) do
    bus = bus_name(bus)

    subscription = %PersistentSubscription{
      concurrency_limit: Keyword.get(opts, :concurrency_limit),
      name: subscription_name,
      partition_by: Keyword.get(opts, :partition_by),
      start_from: start_from,
      stream_id: stream_id
    }

    GenServer.call(bus, {:subscribe_persistent, subscription, subscriber})
  end

  @impl Jido.Bus.Adapter
  def ack(bus, subscription, %RecordedSignal{} = signal) when is_pid(subscription) do
    bus = bus_name(bus)

    GenServer.call(bus, {:ack, signal, subscription})
  end

  @impl Jido.Bus.Adapter
  def unsubscribe(bus, subscription) when is_pid(subscription) do
    bus = bus_name(bus)

    GenServer.call(bus, {:unsubscribe, subscription})
  end

  @impl Jido.Bus.Adapter
  def unsubscribe(bus, stream_id, subscription_name) do
    bus = bus_name(bus)

    GenServer.call(bus, {:unsubscribe, stream_id, subscription_name})
  end

  @impl Jido.Bus.Adapter
  def read_snapshot(bus, source_id) do
    bus = bus_name(bus)

    GenServer.call(bus, {:read_snapshot, source_id})
  end

  @impl Jido.Bus.Adapter
  def record_snapshot(bus, snapshot) do
    bus = bus_name(bus)

    GenServer.call(bus, {:record_snapshot, snapshot})
  end

  @impl Jido.Bus.Adapter
  def delete_snapshot(bus, source_id) do
    bus = bus_name(bus)

    GenServer.call(bus, {:delete_snapshot, source_id})
  end

  def reset!(application, config \\ []) do
    {bus, _config} = parse_config(application, config)

    GenServer.call(bus, :reset!)
  end

  @impl GenServer
  def handle_call({:append, stream_id, expected_version, signals}, _from, %State{} = state) do
    %State{streams: streams} = state

    stream_signals = Map.get(streams, stream_id)

    {reply, state} =
      case {expected_version, stream_signals} do
        {:any_version, nil} ->
          persist_signals(state, stream_id, [], signals)

        {:any_version, stream_signals} ->
          persist_signals(state, stream_id, stream_signals, signals)

        {:no_stream, stream_signals} when is_list(stream_signals) ->
          {{:error, :stream_exists}, state}

        {:no_stream, nil} ->
          persist_signals(state, stream_id, [], signals)

        {:stream_exists, nil} ->
          {{:error, :stream_not_found}, state}

        {:stream_exists, stream_signals} ->
          persist_signals(state, stream_id, stream_signals, signals)

        {0, nil} ->
          persist_signals(state, stream_id, [], signals)

        {expected_version, nil} when is_integer(expected_version) ->
          {{:error, :wrong_expected_version}, state}

        {expected_version, stream_signals}
        when is_integer(expected_version) and length(stream_signals) != expected_version ->
          {{:error, :wrong_expected_version}, state}

        {expected_version, stream_signals}
        when is_integer(expected_version) and length(stream_signals) == expected_version ->
          persist_signals(state, stream_id, stream_signals, signals)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:replay, stream_id, start_version}, _from, %State{} = state) do
    %State{streams: streams} = state

    reply =
      case Map.get(streams, stream_id) do
        nil ->
          {:error, :stream_not_found}

        signals ->
          signals
          |> Enum.reverse()
          |> Stream.drop(max(0, start_version - 1))
          |> Stream.map(&deserialize(state, &1))
          |> Enum.map(&set_signal_number_from_version(&1, stream_id))
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:subscribe, stream_id, subscriber}, _from, %State{} = state) do
    %State{transient_subscribers: transient_subscribers} = state

    Process.monitor(subscriber)

    transient_subscribers =
      Map.update(transient_subscribers, stream_id, [subscriber], fn subscribers ->
        [subscriber | subscribers]
      end)

    state = %State{state | transient_subscribers: transient_subscribers}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe_persistent, subscription, subscriber}, _from, %State{} = state) do
    %PersistentSubscription{name: subscription_name} = subscription
    %State{persistent_subscriptions: persistent_subscriptions} = state

    {reply, state} =
      case Map.get(persistent_subscriptions, subscription_name) do
        nil ->
          start_persistent_subscription(state, subscription, subscriber)

        %PersistentSubscription{subscribers: []} = subscription ->
          start_persistent_subscription(state, subscription, subscriber)

        %PersistentSubscription{concurrency_limit: nil} ->
          {{:error, :subscription_already_exists}, state}

        %PersistentSubscription{} = subscription ->
          %PersistentSubscription{concurrency_limit: concurrency_limit, subscribers: subscribers} =
            subscription

          if length(subscribers) < concurrency_limit do
            start_persistent_subscription(state, subscription, subscriber)
          else
            {{:error, :too_many_subscribers}, state}
          end
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, pid}, _from, %State{} = state) do
    state =
      update_persistent_subscription(state, pid, fn %PersistentSubscription{} = subscription ->
        :ok = stop_subscription(state, pid)

        PersistentSubscription.unsubscribe(subscription, pid)
      end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, stream_id, subscription_name}, _from, %State{} = state) do
    %State{persistent_subscriptions: persistent_subscriptions} = state

    {reply, state} =
      case Map.get(persistent_subscriptions, subscription_name) do
        %PersistentSubscription{stream_id: ^stream_id, subscribers: []} ->
          state = %State{
            state
            | persistent_subscriptions: Map.delete(persistent_subscriptions, subscription_name)
          }

          {:ok, state}

        nil ->
          {{:error, :subscription_not_found}, state}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:read_snapshot, source_id}, _from, %State{} = state) do
    %State{snapshots: snapshots} = state

    reply =
      case Map.get(snapshots, source_id, nil) do
        nil -> {:error, :snapshot_not_found}
        snapshot -> {:ok, deserialize(state, snapshot)}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:record_snapshot, %Snapshot{} = snapshot}, _from, %State{} = state) do
    %Snapshot{source_id: source_id} = snapshot
    %State{snapshots: snapshots} = state

    state = %State{state | snapshots: Map.put(snapshots, source_id, serialize(state, snapshot))}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete_snapshot, source_id}, _from, %State{} = state) do
    %State{snapshots: snapshots} = state

    state = %State{state | snapshots: Map.delete(snapshots, source_id)}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:reset!, _from, %State{} = state) do
    %State{name: name, serializer: serializer, persistent_subscriptions: persistent_subscriptions} =
      state

    for {_name, %PersistentSubscription{subscribers: subscribers}} <- persistent_subscriptions do
      for %{pid: pid} <- subscribers, is_pid(pid) do
        stop_subscription(state, pid)
      end
    end

    initial_state = %State{name: name, serializer: serializer}

    {:reply, :ok, initial_state}
  end

  @impl GenServer
  def handle_call({:ack, signal, subscriber}, _from, %State{} = state) do
    state = ack_persistent_subscription_by_pid(state, signal, subscriber)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    state =
      state
      |> remove_persistent_subscription_by_pid(pid)
      |> remove_transient_subscriber_by_pid(pid)

    {:noreply, state}
  end

  defp persist_signals(%State{} = state, stream_id, existing_signals, new_signals) do
    %State{
      next_signal_number: next_signal_number,
      persisted_signals: persisted_signals,
      persistent_subscriptions: persistent_subscriptions,
      streams: streams
    } = state

    initial_stream_version = length(existing_signals) + 1
    now = DateTime.utc_now()

    new_signals =
      new_signals
      |> Enum.with_index(0)
      |> Enum.map(fn {recorded_signal, index} ->
        signal_number = next_signal_number + index
        stream_version = initial_stream_version + index

        map_to_recorded_signal(signal_number, stream_id, stream_version, now, recorded_signal)
      end)
      |> Enum.map(&serialize(state, &1))

    stream_signals = prepend(existing_signals, new_signals)
    next_signal_number = List.last(new_signals).signal_number + 1

    state = %State{
      state
      | streams: Map.put(streams, stream_id, stream_signals),
        persisted_signals: prepend(persisted_signals, new_signals),
        next_signal_number: next_signal_number
    }

    publish_all_signals = Enum.map(new_signals, &deserialize(state, &1))

    publish_stream_signals =
      Enum.map(publish_all_signals, &set_signal_number_from_version(&1, stream_id))

    state = publish_to_transient_subscribers(state, :all, publish_all_signals)
    state = publish_to_transient_subscribers(state, stream_id, publish_stream_signals)

    persistent_subscriptions =
      Enum.into(persistent_subscriptions, %{}, fn {subscription_name, subscription} ->
        {subscription_name, publish_signals(state, subscription)}
      end)

    state = %State{state | persistent_subscriptions: persistent_subscriptions}

    {:ok, state}
  end

  defp set_signal_number_from_version(%RecordedSignal{} = signal, :all), do: signal

  # Signal number should equal stream version for stream signals.
  defp set_signal_number_from_version(%RecordedSignal{} = signal, _stream_id) do
    %RecordedSignal{stream_version: stream_version} = signal

    %RecordedSignal{signal | signal_number: stream_version}
  end

  defp prepend(list, []), do: list
  defp prepend(list, [item | remainder]), do: prepend([item | list], remainder)

  defp map_to_recorded_signal(
         signal_number,
         stream_id,
         stream_version,
         now,
         %Signal{} = signal
       ) do
    %Signal{
      jido_causation_id: jido_causation_id,
      jido_correlation_id: jido_correlation_id,
      type: type,
      data: data,
      metadata: metadata
    } = signal

    %RecordedSignal{
      signal_id: UUID.uuid4(),
      signal_number: signal_number,
      stream_id: stream_id,
      stream_version: stream_version,
      jido_causation_id: jido_causation_id,
      jido_correlation_id: jido_correlation_id,
      type: type,
      data: data,
      metadata: metadata,
      created_at: now
    }
  end

  defp start_persistent_subscription(%State{} = state, subscription, subscriber) do
    %State{name: bus_name, persistent_subscriptions: persistent_subscriptions} = state
    %PersistentSubscription{name: subscription_name, checkpoint: checkpoint} = subscription

    supervisor_name = subscriptions_supervisor_name(bus_name)
    subscription_spec = Subscription.child_spec(subscriber) |> Map.put(:restart, :temporary)

    {:ok, pid} = DynamicSupervisor.start_child(supervisor_name, subscription_spec)

    Process.monitor(pid)

    checkpoint = if is_nil(checkpoint), do: start_from(state, subscription), else: checkpoint

    subscription = PersistentSubscription.subscribe(subscription, pid, checkpoint)
    subscription = publish_signals(state, subscription)

    persistent_subscriptions = Map.put(persistent_subscriptions, subscription_name, subscription)

    state = %State{state | persistent_subscriptions: persistent_subscriptions}

    {{:ok, pid}, state}
  end

  defp publish_signals(%State{} = state, %PersistentSubscription{} = subscription) do
    %State{persisted_signals: persisted_signals, streams: streams} = state
    %PersistentSubscription{checkpoint: checkpoint, stream_id: stream_id} = subscription

    signals =
      case stream_id do
        :all -> persisted_signals
        stream_id -> Map.get(streams, stream_id, [])
      end

    position = if checkpoint == 0, do: -1, else: -(checkpoint + 1)

    case Enum.at(signals, position) do
      %RecordedSignal{} = unseen_signal ->
        unseen_signal =
          deserialize(state, unseen_signal) |> set_signal_number_from_version(stream_id)

        case PersistentSubscription.publish(subscription, unseen_signal) do
          {:ok, subscription} -> publish_signals(state, subscription)
          {:error, :no_subscriber_available} -> subscription
        end

      nil ->
        subscription
    end
  end

  defp stop_subscription(%State{} = state, subscription) do
    %State{name: name} = state

    supervisor_name = subscriptions_supervisor_name(name)

    DynamicSupervisor.terminate_child(supervisor_name, subscription)
  end

  defp ack_persistent_subscription_by_pid(%State{} = state, %RecordedSignal{} = signal, pid) do
    %RecordedSignal{signal_number: signal_number} = signal

    update_persistent_subscription(state, pid, fn %PersistentSubscription{} = subscription ->
      case PersistentSubscription.ack(subscription, signal_number) do
        %PersistentSubscription{} = subscription ->
          publish_signals(state, subscription)

        {:error, :unexpected_ack} ->
          # We tried to ack an signal but there is no matching in-flight signal
          # I *think* it's okay to ignore this and leave the subscription as is
          subscription
      end
    end)
  end

  defp remove_persistent_subscription_by_pid(%State{} = state, pid) do
    update_persistent_subscription(state, pid, fn %PersistentSubscription{} = subscription ->
      subscription = PersistentSubscription.unsubscribe(subscription, pid)

      publish_signals(state, subscription)
    end)
  end

  defp update_persistent_subscription(%State{} = state, pid, updater)
       when is_function(updater, 1) do
    %State{persistent_subscriptions: persistent_subscriptions} = state

    case find_persistent_subscription(persistent_subscriptions, pid) do
      {subscription_name, %PersistentSubscription{} = subscription} ->
        updated_subscription = updater.(subscription)

        persistent_subscriptions =
          Map.put(persistent_subscriptions, subscription_name, updated_subscription)

        %State{state | persistent_subscriptions: persistent_subscriptions}

      _ ->
        state
    end
  end

  defp find_persistent_subscription(persistent_subscriptions, pid) do
    Enum.find(persistent_subscriptions, fn {_name, %PersistentSubscription{} = subscription} ->
      PersistentSubscription.has_subscriber?(subscription, pid)
    end)
  end

  defp remove_transient_subscriber_by_pid(%State{} = state, pid) do
    %State{transient_subscribers: transient_subscribers} = state

    transient_subscribers =
      Enum.reduce(transient_subscribers, transient_subscribers, fn
        {stream_id, subscribers}, acc ->
          Map.put(acc, stream_id, List.delete(subscribers, pid))
      end)

    %State{state | transient_subscribers: transient_subscribers}
  end

  defp start_from(%State{} = state, %PersistentSubscription{} = subscription) do
    %State{persisted_signals: persisted_signals, streams: streams} = state
    %PersistentSubscription{start_from: start_from, stream_id: stream_id} = subscription

    case {start_from, stream_id} do
      {:current, :all} -> length(persisted_signals)
      {:current, stream_id} -> Map.get(streams, stream_id, []) |> length()
      {:origin, _stream_id} -> 0
      {position, _stream_id} when is_integer(position) -> position
    end
  end

  defp publish_to_transient_subscribers(%State{} = state, stream_id, signals) do
    %State{transient_subscribers: transient_subscribers} = state

    subscribers = Map.get(transient_subscribers, stream_id, [])

    for subscriber <- subscribers, &is_pid/1 do
      send(subscriber, {:signals, signals})
    end

    state
  end

  defp serialize(%State{serializer: nil}, data), do: data

  defp serialize(%State{} = state, %RecordedSignal{} = recorded_signal) do
    %State{serializer: serializer} = state
    %RecordedSignal{data: data, metadata: metadata} = recorded_signal

    %RecordedSignal{
      recorded_signal
      | data: serializer.serialize(data),
        metadata: serializer.serialize(metadata)
    }
  end

  defp serialize(%State{} = state, %Snapshot{} = snapshot) do
    %State{serializer: serializer} = state
    %Snapshot{data: data, metadata: metadata} = snapshot

    %Snapshot{
      snapshot
      | data: serializer.serialize(data),
        metadata: serializer.serialize(metadata)
    }
  end

  defp deserialize(%State{serializer: nil}, data), do: data

  defp deserialize(%State{} = state, %RecordedSignal{} = recorded_signal) do
    %State{serializer: serializer} = state
    %RecordedSignal{data: data, metadata: metadata, type: type} = recorded_signal

    %RecordedSignal{
      recorded_signal
      | data: serializer.deserialize(data, type: type),
        metadata: serializer.deserialize(metadata)
    }
  end

  defp deserialize(%State{} = state, %Snapshot{} = snapshot) do
    %State{serializer: serializer} = state
    %Snapshot{data: data, metadata: metadata, source_type: source_type} = snapshot

    %Snapshot{
      snapshot
      | data: serializer.deserialize(data, type: source_type),
        metadata: serializer.deserialize(metadata)
    }
  end

  defp parse_config(application, config) do
    case Keyword.get(config, :name) do
      nil ->
        name = Module.concat([application, Bus])
        {name, Keyword.put(config, :name, name)}

      name when is_atom(name) ->
        {name, config}

      invalid ->
        raise ArgumentError,
          message:
            "expected :name option to be an atom but got: " <>
              inspect(invalid)
    end
  end

  defp bus_name(bus) when is_map(bus),
    do: Map.get(bus, :name)

  defp subscriptions_supervisor_name(bus),
    do: Module.concat([bus, SubscriptionsSupervisor])
end
