defmodule Jido.Signal.Bus.Stream do
  @moduledoc """
  Provides streaming functionality for the signal bus.

  This module contains functions for filtering, processing, and publishing
  signals through the bus streaming interface. It supports operations like
  filtering signals by type pattern and timestamp, as well as publishing
  signals to subscribers.
  """

  use ExDbug, enabled: false
  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Router
  alias Jido.Signal
  require Logger

  @doc """
  Filters signals from the bus state's log based on type pattern and timestamp.
  The type pattern is used for matching against the signal's type field.
  """
  def filter(%BusState{} = state, type_pattern, start_timestamp \\ nil, opts \\ []) do
    try do
      batch_size = Keyword.get(opts, :batch_size, 1_000)
      correlation_id = Keyword.get(opts, :correlation_id)

      # Get list of signals from log map
      signals = BusState.log_to_list(state)

      dbug("Filtering signals",
        signal_count: length(signals),
        type_pattern: type_pattern,
        start_timestamp: start_timestamp
      )

      # First filter by timestamp if provided
      timestamp_filtered =
        if start_timestamp do
          filtered =
            Enum.filter(signals, fn signal ->
              # For UUID7 IDs, we can extract the timestamp directly from the ID
              # This is more efficient than converting DateTime to Unix time
              # Fall back to created_at if ID timestamp extraction fails
              signal_ts =
                try do
                  ts = Jido.Signal.ID.extract_timestamp(signal.id)

                  dbug("Signal timestamp",
                    signal_id: signal.id,
                    timestamp: ts,
                    start_timestamp: start_timestamp
                  )

                  ts
                rescue
                  _error ->
                    dbug("Failed to extract timestamp", error: _error)
                    # Default to 0 to include the signal
                    0
                end

              signal_ts > start_timestamp
            end)

          dbug("After timestamp filtering",
            filtered_count: length(filtered),
            original_count: length(signals)
          )

          filtered
        else
          signals
        end

      # Then filter by correlation_id if provided
      correlation_filtered =
        if correlation_id do
          Enum.filter(timestamp_filtered, fn signal ->
            signal.correlation_id == correlation_id
          end)
        else
          timestamp_filtered
        end

      # Finally filter by type pattern
      # We need to check if the pattern is valid first
      case Router.Validator.validate_path(type_pattern) do
        {:ok, _} ->
          # Create a simple pattern matcher function
          matches_pattern? = fn signal ->
            matches = Router.matches?(signal.type, type_pattern)

            dbug("Pattern matching",
              signal_type: signal.type,
              pattern: type_pattern,
              matches: matches
            )

            matches
          end

          # Apply the pattern filter and take the specified batch size
          filtered_signals =
            correlation_filtered
            |> Enum.filter(matches_pattern?)
            |> Enum.take(batch_size)
            |> Enum.map(fn signal ->
              # Convert to RecordedSignal struct
              %Jido.Signal.Bus.RecordedSignal{
                id: signal.id,
                type: signal.type,
                created_at: DateTime.utc_now(),
                signal: signal
              }
            end)

          dbug("Final filtered signals", count: length(filtered_signals))
          {:ok, filtered_signals}

        {:error, reason} ->
          Logger.error("Invalid pattern: #{inspect(reason)}")
          {:error, :invalid_pattern}
      end
    rescue
      error ->
        Logger.error("Error filtering signals: #{inspect(error)}")
        {:error, :filter_failed}
    end
  end

  @doc """
  Publishes signals to the bus, recording them and routing them to subscribers.
  Each signal is routed based on its own type field.
  Only accepts proper Jido.Signal structs to ensure system integrity.
  Signals are recorded and routed in the exact order they are received.
  """

  def publish(%BusState{} = state, signals) when is_list(signals) do
    dbug("publish", signals: signals)

    with :ok <- validate_signals(signals),
         {:ok, new_state, _new_signals} <- BusState.append_signals(state, signals) do
      # Route signals to subscribers
      Enum.each(signals, fn signal ->
        # For each subscription, check if the signal type matches the subscription path
        Enum.each(new_state.subscriptions, fn {_id, subscription} ->
          if Router.matches?(signal.type, subscription.path) do
            # If it matches, dispatch the signal
            Jido.Signal.Dispatch.dispatch(signal, subscription.dispatch)
          end
        end)
      end)

      {:ok, new_state}
    end
  end

  @doc """
  Acknowledges a signal for a given subscription.
  """
  def ack(%BusState{} = state, subscription_id, %Signal{} = signal) do
    dbug("ack", subscription_id: subscription_id, signal: signal)

    case BusState.get_subscription(state, subscription_id) do
      nil ->
        {:error, :subscription_not_found}

      subscription ->
        if subscription.persistent? && subscription.persistence_pid do
          # Send ack to persistent subscription process
          GenServer.cast(subscription.persistence_pid, {:ack, signal.id})
          {:ok, state}
        else
          # Non-persistent subscriptions don't need acks
          {:ok, state}
        end
    end
  end

  @doc """
  Truncates the signal log to the specified maximum size.
  Keeps the most recent signals and discards older ones.
  """
  def truncate(%BusState{} = state, max_size) when is_integer(max_size) and max_size >= 0 do
    BusState.truncate_log(state, max_size)
  end

  @doc """
  Clears all signals from the log.
  """
  def clear(%BusState{} = state) do
    BusState.clear_log(state)
  end

  defp validate_signals(signals) do
    invalid_signals =
      Enum.reject(signals, fn signal ->
        is_struct(signal, Signal)
      end)

    case invalid_signals do
      [] -> :ok
      _ -> {:error, :invalid_signals}
    end
  end
end
