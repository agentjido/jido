defmodule Jido.Signal.Bus.Subscriber do
  @moduledoc """
  Defines the subscriber model and subscription management for the signal bus.

  This module contains the subscriber type definition and functions for creating,
  managing, and dispatching signals to subscribers. It supports both regular and
  persistent subscriptions, handling subscription lifetime and signal delivery.
  """

  use Private
  use TypedStruct
  use ExDbug, enabled: false

  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Error

  typedstruct do
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:dispatch, term(), enforce: true)
    field(:persistent?, boolean(), default: false)
    field(:persistence_pid, pid(), default: nil)
    field(:disconnected?, boolean(), default: false)
    field(:created_at, DateTime.t(), default: DateTime.utc_now())
  end

  @spec subscribe(BusState.t(), String.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Error.t()}
  def subscribe(%BusState{} = state, subscription_id, path, opts) do
    dbug("subscribe", state: state, subscription_id: subscription_id, path: path, opts: opts)
    persistent? = Keyword.get(opts, :persistent?, false)
    dispatch = Keyword.get(opts, :dispatch)

    # Check if subscription already exists
    if BusState.has_subscription?(state, subscription_id) do
      dbug("subscription already exists", subscription_id: subscription_id)

      {:error,
       Error.validation_error("Subscription already exists", %{
         subscription_id: subscription_id
       })}
    else
      # Create the subscription struct
      subscription = %Subscriber{
        id: subscription_id,
        path: path,
        dispatch: dispatch,
        persistent?: persistent?,
        persistence_pid: nil,
        created_at: DateTime.utc_now()
      }

      if persistent? do
        dbug("creating persistent subscription", subscription: subscription)
        # Extract the client PID from the dispatch configuration
        client_pid = extract_client_pid(dispatch)

        # Start the persistent subscription process under the bus supervisor
        persistent_sub_opts = [
          id: subscription_id,
          bus_pid: self(),
          bus_subscription: subscription,
          start_from: opts[:start_from] || :origin,
          max_in_flight: opts[:max_in_flight] || 1000,
          client_pid: client_pid
        ]

        case DynamicSupervisor.start_child(
               state.child_supervisor,
               {Jido.Signal.Bus.PersistentSubscription, persistent_sub_opts}
             ) do
          {:ok, pid} ->
            dbug("persistent subscription started", pid: pid)
            # Update subscription with persistence pid
            subscription = %{subscription | persistence_pid: pid}
            BusState.add_subscription(state, subscription_id, subscription)

          {:error, reason} ->
            dbug("failed to start persistent subscription", reason: reason)
            {:error, Error.execution_error("Failed to start persistent subscription", reason)}
        end
      else
        dbug("creating non-persistent subscription", subscription: subscription)
        BusState.add_subscription(state, subscription_id, subscription)
      end
    end
  end

  @spec unsubscribe(BusState.t(), String.t(), keyword()) ::
          {:ok, BusState.t()} | {:error, Error.t()}
  def unsubscribe(%BusState{} = state, subscription_id, _opts \\ []) do
    dbug("unsubscribe", state: state, subscription_id: subscription_id)
    # Get the subscription before removing it
    subscription = BusState.get_subscription(state, subscription_id)

    case BusState.remove_subscription(state, subscription_id) do
      {:ok, new_state} ->
        # If this was a persistent subscription, terminate the process
        if subscription && subscription.persistent? && subscription.persistence_pid do
          dbug("terminating persistent subscription",
            subscription_id: subscription_id,
            persistence_pid: subscription.persistence_pid
          )

          # Send shutdown message to terminate the process gracefully
          Process.send(subscription.persistence_pid, {:shutdown, :normal}, [])
        end

        {:ok, new_state}

      {:error, :subscription_not_found} ->
        dbug("subscription not found", subscription_id: subscription_id)

        {:error,
         Error.validation_error("Subscription does not exist", %{subscription_id: subscription_id})}

      {:error, reason} ->
        dbug("failed to remove subscription", reason: reason)
        {:error, Error.execution_error("Failed to remove subscription", reason)}
    end
  end

  # Helper function to extract client PID from dispatch configuration
  defp extract_client_pid({:pid, opts}) when is_list(opts) do
    dbug("extracting client pid", opts: opts)
    Keyword.get(opts, :target)
  end

  defp extract_client_pid(_) do
    dbug("no client pid found in dispatch config")
    nil
  end
end
