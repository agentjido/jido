defmodule Jido.Signal.Bus.PersistentSubscription do
  @moduledoc """
  A GenServer that manages persistent subscription state and checkpoints for a single subscriber.

  This module maintains the subscription state for a client, tracking which signals have been
  acknowledged and allowing clients to resume from their last checkpoint after disconnection.
  Each instance maps 1:1 to a bus subscriber and is managed as a child of the Bus's dynamic supervisor.
  """
  use GenServer
  use TypedStruct
  require Logger
  use ExDbug, enabled: false
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Dispatch
  alias Jido.Signal.ID

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:bus_pid, pid(), enforce: true)
    field(:bus_subscription, Subscriber.t())

    # Persistent subscription state
    field(:client_pid, pid(), enforce: true)
    field(:checkpoint, non_neg_integer(), default: 0)
    field(:max_in_flight, pos_integer(), default: 1000)
    field(:in_flight_signals, map(), default: %{})
    field(:pending_signals, map(), default: %{})
  end

  # Client API

  @doc """
  Starts a new persistent subscription process.

  Options:
  - id: Unique identifier for this subscription (required)
  - bus_pid: PID of the bus this subscription belongs to (required)
  - path: Signal path pattern to subscribe to (required)
  - start_from: Where to start reading signals from (:origin, :current, or timestamp)
  - max_in_flight: Maximum number of unacknowledged signals
  - client_pid: PID of the client process (required)
  - dispatch_opts: Additional dispatch options for the subscription
  """
  def start_link(opts) do
    id = Jido.Util.generate_id()
    opts = Keyword.put(opts, :id, id)

    # Validate start_from value and set default if invalid
    opts =
      case Keyword.get(opts, :start_from, :origin) do
        :origin ->
          opts

        :current ->
          opts

        timestamp when is_integer(timestamp) and timestamp >= 0 ->
          opts

        _invalid ->
          dbug("Invalid start_from value, using :origin", invalid_value: _invalid)
          Keyword.put(opts, :start_from, :origin)
      end

    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  defdelegate via_tuple(id), to: Jido.Util
  defdelegate whereis(id), to: Jido.Util

  @impl GenServer
  def init(opts) do
    dbug("Initializing persistent subscription", opts: opts)

    # Extract the bus subscription
    bus_subscription = Keyword.fetch!(opts, :bus_subscription)
    dbug("Bus subscription dispatch config", dispatch: bus_subscription.dispatch)

    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      bus_pid: Keyword.fetch!(opts, :bus_pid),
      bus_subscription: bus_subscription,

      #
      client_pid: Keyword.get(opts, :client_pid),
      checkpoint: Keyword.get(opts, :checkpoint, 0),
      max_in_flight: Keyword.get(opts, :max_in_flight, 1000),
      in_flight_signals: %{},
      pending_signals: %{}
    }

    # Monitor the client process if specified
    if state.client_pid && Process.alive?(state.client_pid) do
      dbug("Monitoring client process", client_pid: state.client_pid)
      Process.monitor(state.client_pid)
    end

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:ack, signal_log_id}, _from, state) when is_binary(signal_log_id) do
    dbug("Acknowledging signal",
      id: state.id,
      signal_log_id: signal_log_id,
      current_checkpoint: state.checkpoint
    )

    # Remove the acknowledged signal from in-flight
    new_in_flight = Map.delete(state.in_flight_signals, signal_log_id)

    # Extract timestamp from UUID7 for checkpoint comparison
    timestamp = ID.extract_timestamp(signal_log_id)

    # Update checkpoint if this is a higher number
    new_checkpoint = max(state.checkpoint, timestamp)

    # Update state
    new_state = %{state | in_flight_signals: new_in_flight, checkpoint: new_checkpoint}

    # Process any pending signals
    new_state = process_pending_signals(new_state)

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:ack, signal_log_ids}, _from, state) when is_list(signal_log_ids) do
    dbug("Acknowledging batch of signals",
      id: state.id,
      signal_count: length(signal_log_ids),
      current_checkpoint: state.checkpoint
    )

    # Remove all acknowledged signals from in-flight
    new_in_flight =
      Enum.reduce(signal_log_ids, state.in_flight_signals, fn id, acc ->
        Map.delete(acc, id)
      end)

    # Extract timestamps from all UUIDs and find the highest
    highest_timestamp =
      signal_log_ids
      |> Enum.map(&ID.extract_timestamp/1)
      |> Enum.max()

    # Update checkpoint if this is a higher number
    new_checkpoint = max(state.checkpoint, highest_timestamp)

    # Update state
    new_state = %{state | in_flight_signals: new_in_flight, checkpoint: new_checkpoint}

    # Process any pending signals
    new_state = process_pending_signals(new_state)

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:signal, {signal_log_id, signal}}, _from, state) do
    dbug("Received signal via call", signal_log_id: signal_log_id)

    # Check if we can dispatch this signal immediately or need to queue it
    if map_size(state.in_flight_signals) < state.max_in_flight do
      dbug("Dispatching signal immediately",
        signal_log_id: signal_log_id,
        in_flight_count: map_size(state.in_flight_signals)
      )

      # We have capacity, add to in-flight and dispatch
      new_in_flight = Map.put(state.in_flight_signals, signal_log_id, signal)

      # Dispatch according to subscription dispatch configuration
      if state.bus_subscription.dispatch do
        # Perform the actual dispatch
        dispatch_result = Dispatch.dispatch(signal, state.bus_subscription.dispatch)

        if dispatch_result != :ok do
          dbug("Dispatch failed", result: dispatch_result)
        end
      end

      {:reply, :ok, %{state | in_flight_signals: new_in_flight}}
    else
      dbug("Queue full, adding to pending signals",
        signal_log_id: signal_log_id,
        in_flight_count: map_size(state.in_flight_signals),
        pending_count: map_size(state.pending_signals)
      )

      # We're at capacity, add to pending signals
      new_pending = Map.put(state.pending_signals, signal_log_id, signal)
      {:reply, :ok, %{state | pending_signals: new_pending}}
    end
  end

  @impl GenServer
  def handle_call(_req, _from, state) do
    dbug("Unexpected call", request: _req)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:ack, signal_log_id}, state) when is_binary(signal_log_id) do
    dbug("Acknowledging signal (async)",
      id: state.id,
      signal_log_id: signal_log_id,
      current_checkpoint: state.checkpoint
    )

    # Remove the acknowledged signal from in-flight
    new_in_flight = Map.delete(state.in_flight_signals, signal_log_id)

    # Extract timestamp from UUID7 for checkpoint comparison
    timestamp = ID.extract_timestamp(signal_log_id)

    # Update checkpoint if this is a higher number
    new_checkpoint = max(state.checkpoint, timestamp)

    # Update state
    new_state = %{state | in_flight_signals: new_in_flight, checkpoint: new_checkpoint}

    # Process any pending signals
    new_state = process_pending_signals(new_state)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:reconnect, new_client_pid}, state) do
    dbug("Reconnecting client",
      id: state.id,
      old_client_pid: state.client_pid,
      new_client_pid: new_client_pid,
      bus_subscription: state.bus_subscription,
      checkpoint: state.checkpoint
    )

    # Only proceed if the new client is alive
    if Process.alive?(new_client_pid) do
      # Monitor the new client process
      Process.monitor(new_client_pid)

      # Update the bus subscription to point to the new client PID
      updated_subscription = %{
        state.bus_subscription
        | dispatch: {:pid, target: new_client_pid, delivery_mode: :async}
      }

      dbug("Updated subscription",
        subscription: updated_subscription,
        has_log: Map.has_key?(updated_subscription, :log),
        subscription_keys: Map.keys(updated_subscription)
      )

      # Update state with new client PID and subscription
      new_state = %{state | client_pid: new_client_pid, bus_subscription: updated_subscription}

      # Replay any signals that were missed while disconnected
      new_state = replay_missed_signals(new_state)

      {:noreply, new_state}
    else
      dbug("New client process is not alive", new_client_pid: new_client_pid)
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:signal, {signal_log_id, signal}}, state) do
    dbug("Received signal", signal_log_id: signal_log_id)

    # Check if we can dispatch this signal immediately or need to queue it
    if map_size(state.in_flight_signals) < state.max_in_flight do
      dbug("Dispatching signal immediately",
        signal_log_id: signal_log_id,
        in_flight_count: map_size(state.in_flight_signals)
      )

      # We have capacity, add to in-flight and dispatch
      new_in_flight = Map.put(state.in_flight_signals, signal_log_id, signal)

      # Dispatch according to subscription dispatch configuration
      if state.bus_subscription.dispatch do
        # Perform the actual dispatch
        dispatch_result = Dispatch.dispatch(signal, state.bus_subscription.dispatch)

        if dispatch_result != :ok do
          dbug("Dispatch failed", result: dispatch_result)
        end
      end

      {:noreply, %{state | in_flight_signals: new_in_flight}}
    else
      dbug("Queue full, adding to pending signals",
        signal_log_id: signal_log_id,
        in_flight_count: map_size(state.in_flight_signals),
        pending_count: map_size(state.pending_signals)
      )

      # We're at capacity, add to pending signals
      new_pending = Map.put(state.pending_signals, signal_log_id, signal)
      {:noreply, %{state | pending_signals: new_pending}}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{client_pid: client_pid} = state)
      when pid == client_pid do
    dbug("Client process down",
      client_pid: client_pid,
      reason: _reason,
      subscription_id: state.id
    )

    # Client disconnected, but we keep the subscription alive
    # The client can reconnect later using the reconnect/2 function
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    dbug("Unexpected message", msg: _msg)
    {:noreply, state}
  end

  # Helper function to replay missed signals
  defp replay_missed_signals(state) do
    Logger.debug("Replaying missed signals for subscription #{state.id}")

    dbug("Replay state",
      subscription_id: state.id,
      checkpoint: state.checkpoint,
      bus_subscription: state.bus_subscription,
      has_log: Map.has_key?(state.bus_subscription, :log),
      subscription_keys: Map.keys(state.bus_subscription)
    )

    # Get the bus state to access the log
    bus_state = :sys.get_state(state.bus_pid)

    dbug("Bus state",
      has_log: Map.has_key?(bus_state, :log),
      log_keys: Map.keys(bus_state.log),
      log_count: map_size(bus_state.log)
    )

    missed_signals =
      Enum.filter(bus_state.log, fn {_id, signal} ->
        case DateTime.from_iso8601(signal.time) do
          {:ok, timestamp, _offset} -> DateTime.to_unix(timestamp) > state.checkpoint
          _ -> false
        end
      end)

    dbug("Missed signals",
      count: length(missed_signals),
      signal_types: Enum.map(missed_signals, fn {_id, signal} -> signal.type end)
    )

    Enum.each(missed_signals, fn {_id, signal} ->
      case DateTime.from_iso8601(signal.time) do
        {:ok, timestamp, _offset} ->
          if DateTime.to_unix(timestamp) > state.checkpoint do
            if state.bus_subscription.dispatch do
              dispatch_result = Dispatch.dispatch(signal, state.bus_subscription.dispatch)

              if dispatch_result != :ok do
                Logger.debug(
                  "Dispatch failed during replay, signal: #{inspect(signal)}, dispatch_result: #{inspect(dispatch_result)}"
                )
              end
            end
          end

        _ ->
          :ok
      end
    end)

    state
  end

  @impl GenServer
  def terminate(_reason, state) do
    dbug("Terminating persistent subscription",
      id: state.id,
      reason: _reason
    )

    # Use state.id as the subscription_id since that's what we're using to identify the subscription
    if state.bus_pid do
      # Best effort to unsubscribe
      Jido.Signal.Bus.unsubscribe(state.bus_pid, state.id)
    end

    :ok
  end

  # Private Helpers

  # Helper function to process pending signals if we have capacity
  defp process_pending_signals(state) do
    # Check if we have pending signals and space in the in-flight queue
    available_capacity = state.max_in_flight - map_size(state.in_flight_signals)

    dbug("Processing pending signals",
      available_capacity: available_capacity,
      pending_count: map_size(state.pending_signals)
    )

    if available_capacity > 0 && map_size(state.pending_signals) > 0 do
      # Get the first pending signal (using Enum.at to get the first key-value pair)
      {signal_id, signal} =
        state.pending_signals
        |> Enum.sort_by(fn {id, _} -> id end)
        |> List.first()

      dbug("Processing pending signal",
        signal_id: signal_id,
        client_pid: state.client_pid
      )

      # Remove from pending
      new_pending = Map.delete(state.pending_signals, signal_id)

      # Add to in-flight
      new_in_flight = Map.put(state.in_flight_signals, signal_id, signal)

      # Dispatch the signal using the configured dispatch mechanism
      if state.bus_subscription.dispatch do
        dispatch_result = Dispatch.dispatch(signal, state.bus_subscription.dispatch)

        if dispatch_result != :ok do
          dbug("Dispatch of pending signal failed", result: dispatch_result)
        end
      end

      # Update state
      new_state = %{state | in_flight_signals: new_in_flight, pending_signals: new_pending}

      # Recursively process more pending signals if available
      process_pending_signals(new_state)
    else
      # No change needed
      state
    end
  end
end
