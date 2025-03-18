defmodule Jido.Signal.Bus.State do
  @moduledoc """
  Defines the state structure for the signal bus.

  This module contains the type definitions and operations for managing
  the internal state of the signal bus, including signal logs, subscriptions,
  snapshots, and router configuration. It provides functions for manipulating
  and querying this state.
  """

  use TypedStruct
  use ExDbug, enabled: false

  alias Jido.Signal
  alias Jido.Signal.Router

  typedstruct do
    field(:name, atom(), enforce: true)
    field(:router, Router.Router.t(), default: Router.new!())
    field(:log, %{String.t() => Signal.t()}, default: %{})
    field(:snapshots, %{String.t() => Signal.t()}, default: %{})
    field(:subscriptions, %{String.t() => Jido.Signal.Bus.Subscriber.t()}, default: %{})
    field(:child_supervisor, pid())
  end

  @doc """
  Merges a list of recorded signals into the existing log.
  Signals are added to the log keyed by their IDs.
  If a signal with the same ID already exists, it will be overwritten.

  ## Parameters
    - state: The current bus state
    - signals: List of recorded signals to merge

  ## Returns
    - {:ok, new_state, recorded_signals} with signals merged into log
    - {:error, reason} if there was an error processing the signals
  """
  @spec append_signals(t(), list(Jido.Signal.t() | {:ok, Jido.Signal.t()} | map())) ::
          {:ok, t(), list(Signal.t())} | {:error, term()}
  def append_signals(%__MODULE__{} = state, signals) when is_list(signals) do
    try do
      {uuids, _timestamp} = Jido.Signal.ID.generate_batch(length(signals))

      new_log =
        uuids
        |> Enum.zip(signals)
        |> Enum.reduce(state.log, fn {uuid, signal}, acc ->
          # Use the UUID as the key for the signal
          Map.put(acc, uuid, signal)
        end)

      {:ok, %{state | log: new_log}, signals}
    rescue
      e in KeyError ->
        {:error, "Invalid signal format: #{Exception.message(e)}"}

      e ->
        {:error, "Error processing signals: #{Exception.message(e)}"}
    end
  end

  def log_to_list(%__MODULE__{} = state) do
    state.log
    |> Map.values()
    |> Enum.sort_by(fn signal -> signal.id end)
  end

  @doc """
  Truncates the signal log to the specified maximum size.
  Keeps the most recent signals and discards older ones.
  """
  def truncate_log(%__MODULE__{} = state, max_size) when is_integer(max_size) and max_size >= 0 do
    if map_size(state.log) <= max_size do
      # No truncation needed
      {:ok, state}
    else
      sorted_signals =
        state.log
        |> Enum.sort_by(fn {key, _signal} -> key end)
        |> Enum.map(fn {_key, signal} -> signal end)

      # Keep only the most recent max_size signals
      to_keep = Enum.take(sorted_signals, -max_size)

      # Convert back to map
      truncated_log = Map.new(to_keep, fn signal -> {signal.id, signal} end)

      {:ok, %{state | log: truncated_log}}
    end
  end

  @doc """
  Clears all signals from the log.
  """
  def clear_log(%__MODULE__{} = state) do
    {:ok, %{state | log: %{}}}
  end

  def add_route(%__MODULE__{} = state, route) do
    case Router.add(state.router, route) do
      {:ok, new_router} -> {:ok, %{state | router: new_router}}
      {:error, reason} -> {:error, reason}
    end
  end

  def remove_route(%__MODULE__{} = state, %Router.Route{} = route) do
    # Extract the path from the route
    path = route.path

    # Check if the route exists before trying to remove it
    {:ok, routes} = Router.list(state.router)
    route_exists = Enum.any?(routes, fn r -> r.path == path end)

    if route_exists do
      case Router.remove(state.router, path) do
        {:ok, new_router} -> {:ok, %{state | router: new_router}}
        _ -> {:error, :route_not_found}
      end
    else
      {:error, :route_not_found}
    end
  end

  def remove_route(%__MODULE__{} = state, path) when is_binary(path) do
    # Check if the route exists before trying to remove it
    {:ok, routes} = Router.list(state.router)
    route_exists = Enum.any?(routes, fn r -> r.path == path end)

    if route_exists do
      case Router.remove(state.router, path) do
        {:ok, new_router} -> {:ok, %{state | router: new_router}}
        _ -> {:error, :route_not_found}
      end
    else
      {:error, :route_not_found}
    end
  end

  def has_subscription?(%__MODULE__{} = state, subscription_id) do
    Map.has_key?(state.subscriptions, subscription_id)
  end

  def get_subscription(%__MODULE__{} = state, subscription_id) do
    Map.get(state.subscriptions, subscription_id)
  end

  def add_subscription(%__MODULE__{} = state, subscription_id, subscription) do
    if has_subscription?(state, subscription_id) do
      {:error, :subscription_exists}
    else
      new_state = %{
        state
        | subscriptions: Map.put(state.subscriptions, subscription_id, subscription)
      }

      add_route(new_state, subscription_to_route(subscription))
    end
  end

  def remove_subscription(%__MODULE__{} = state, subscription_id, opts \\ []) do
    delete_persistence = Keyword.get(opts, :delete_persistence, true)

    if has_subscription?(state, subscription_id) && delete_persistence do
      {subscription, new_subscriptions} = Map.pop(state.subscriptions, subscription_id)
      new_state = %{state | subscriptions: new_subscriptions}

      case Router.remove(new_state.router, subscription.path) do
        {:ok, new_router} -> {:ok, %{new_state | router: new_router}}
        _ -> {:error, :route_not_found}
      end
    else
      {:error, :subscription_not_found}
    end
  end

  defp subscription_to_route(subscription) do
    %Router.Route{
      # Use the path pattern for matching
      path: subscription.path,
      target: subscription.dispatch,
      priority: 0,
      # Let the Router's path matching handle wildcards
      match: nil
    }
  end
end
