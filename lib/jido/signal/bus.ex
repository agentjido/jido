defmodule Jido.Signal.Bus do
  @moduledoc """
  Implements a signal bus for routing, filtering, and distributing signals.

  The Bus acts as a central hub for signals in the system, allowing components
  to publish and subscribe to signals. It handles routing based on signal paths,
  subscription management, persistence, and signal filtering. The Bus maintains
  an internal log of signals and provides mechanisms for retrieving historical
  signals and snapshots.
  """

  use GenServer
  require Logger
  use ExDbug, enabled: false
  use TypedStruct
  alias Jido.Signal.Router
  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Bus.Stream
  alias Jido.Signal.Bus.Snapshot
  alias Jido.Error

  @type start_option ::
          {:name, atom()}
          | {atom(), term()}

  @type server ::
          pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}
  @type path :: Router.path()
  @type subscription_id :: String.t()

  @doc """
  Returns a child specification for starting the bus under a supervisor.

  ## Options

  - name: The name to register the bus under (required)
  - router: A custom router implementation (optional)
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Starts a new bus process.
  Options:
  - name: The name to register the bus under (required)
  - router: A custom router implementation (optional)
  """
  @impl GenServer
  def init({name, opts}) do
    dbug("init", name: name, opts: opts)
    # Trap exits so we can handle subscriber termination
    Process.flag(:trap_exit, true)

    {:ok, child_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    state = %BusState{
      name: name,
      router: Keyword.get(opts, :router, Router.new!()),
      child_supervisor: child_supervisor
    }

    {:ok, state}
  end

  def start_link(opts) do
    dbug("start_link", opts: opts)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, {name, opts}, name: via_tuple(name, opts))
  end

  defdelegate via_tuple(name, opts \\ []), to: Jido.Util
  defdelegate whereis(server, opts \\ []), to: Jido.Util

  @doc """
  Subscribes to signals matching the given path pattern.
  Options:
  - dispatch: How to dispatch signals to the subscriber (default: async to calling process)
  - persistent: Whether the subscription should persist across restarts (default: false)
  """
  @spec subscribe(server(), path(), Keyword.t()) :: {:ok, subscription_id()} | {:error, term()}
  def subscribe(bus, path, opts \\ []) do
    # Ensure we have a dispatch configuration
    opts =
      if Keyword.has_key?(opts, :dispatch) do
        # Ensure dispatch has delivery_mode: :async
        dispatch = Keyword.get(opts, :dispatch)

        dispatch =
          case dispatch do
            {:pid, pid_opts} ->
              {:pid, Keyword.put(pid_opts, :delivery_mode, :async)}

            other ->
              other
          end

        Keyword.put(opts, :dispatch, dispatch)
      else
        Keyword.put(opts, :dispatch, {:pid, target: self(), delivery_mode: :async})
      end

    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:subscribe, path, opts})
    end
  end

  @doc """
  Unsubscribes from signals using the subscription ID.
  Options:
  - delete_persistence: Whether to delete persistent subscription data (default: false)
  """
  @spec unsubscribe(server(), subscription_id(), Keyword.t()) :: :ok | {:error, term()}
  def unsubscribe(bus, subscription_id, opts \\ []) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:unsubscribe, subscription_id, opts})
    end
  end

  @doc """
  Publishes a list of signals to the bus.
  Returns {:ok, recorded_signals} on success.
  """
  @spec publish(server(), [Jido.Signal.t()]) ::
          {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}
  def publish(_bus, []) do
    {:ok, []}
  end

  def publish(bus, signals) when is_list(signals) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:publish, signals})
    end
  end

  @doc """
  Replays signals from the bus log that match the given path pattern.
  Optional start_timestamp to replay from a specific point in time.
  """
  @spec replay(server(), path(), non_neg_integer(), Keyword.t()) ::
          {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}
  def replay(bus, path \\ "*", start_timestamp \\ 0, opts \\ []) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:replay, path, start_timestamp, opts})
    end
  end

  @doc """
  Creates a new snapshot of signals matching the given path pattern.
  """
  @spec snapshot_create(server(), path()) :: {:ok, Snapshot.SnapshotRef.t()} | {:error, term()}
  def snapshot_create(bus, path) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:snapshot_create, path})
    end
  end

  @doc """
  Lists all available snapshots.
  """
  @spec snapshot_list(server()) :: [Snapshot.SnapshotRef.t()]
  def snapshot_list(bus) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, :snapshot_list)
    end
  end

  @doc """
  Reads a snapshot by its ID.
  """
  @spec snapshot_read(server(), String.t()) :: {:ok, Snapshot.SnapshotData.t()} | {:error, term()}
  def snapshot_read(bus, snapshot_id) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:snapshot_read, snapshot_id})
    end
  end

  @doc """
  Deletes a snapshot by its ID.
  """
  @spec snapshot_delete(server(), String.t()) :: :ok | {:error, term()}
  def snapshot_delete(bus, snapshot_id) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:snapshot_delete, snapshot_id})
    end
  end

  @doc """
  Acknowledges a signal for a persistent subscription.
  """
  @spec ack(server(), subscription_id(), String.t() | integer()) :: :ok | {:error, term()}
  def ack(bus, subscription_id, signal_id) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:ack, subscription_id, signal_id})
    end
  end

  @doc """
  Reconnects a client to a persistent subscription.
  """
  @spec reconnect(server(), subscription_id(), pid()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def reconnect(bus, subscription_id, client_pid) do
    with {:ok, pid} <- whereis(bus) do
      GenServer.call(pid, {:reconnect, subscription_id, client_pid})
    end
  end

  @impl GenServer
  def handle_call({:subscribe, path, opts}, _from, state) do
    subscription_id = Keyword.get(opts, :subscription_id, Jido.Util.generate_id())
    opts = Keyword.put(opts, :subscription_id, subscription_id)

    case Jido.Signal.Bus.Subscriber.subscribe(state, subscription_id, path, opts) do
      {:ok, new_state} -> {:reply, {:ok, subscription_id}, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:unsubscribe, subscription_id, opts}, _from, state) do
    case Jido.Signal.Bus.Subscriber.unsubscribe(state, subscription_id, opts) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:publish, signals}, _from, state) do
    case Stream.publish(state, signals) do
      {:ok, new_state} ->
        # Extract the signals from the log that we just added
        # We need to return the recorded signals, not the state
        recorded_signals =
          signals
          |> Enum.map(fn signal ->
            # Create a RecordedSignal struct for each signal
            %Jido.Signal.Bus.RecordedSignal{
              id: signal.id,
              type: signal.type,
              created_at: DateTime.utc_now(),
              signal: signal
            }
          end)

        {:reply, {:ok, recorded_signals}, new_state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:replay, path, start_timestamp, opts}, _from, state) do
    case Stream.filter(state, path, start_timestamp, opts) do
      {:ok, signals} -> {:reply, {:ok, signals}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:snapshot_create, path}, _from, state) do
    case Snapshot.create(state, path) do
      {:ok, snapshot_ref, new_state} -> {:reply, {:ok, snapshot_ref}, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call(:snapshot_list, _from, state) do
    {:reply, Snapshot.list(state), state}
  end

  def handle_call({:snapshot_read, snapshot_id}, _from, state) do
    case Snapshot.read(state, snapshot_id) do
      {:ok, snapshot_data} -> {:reply, {:ok, snapshot_data}, state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:snapshot_delete, snapshot_id}, _from, state) do
    case Snapshot.delete(state, snapshot_id) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, error} -> {:reply, {:error, error}, state}
    end
  end

  def handle_call({:ack, subscription_id, _signal_id}, _from, state) do
    # Check if the subscription exists
    subscription = BusState.get_subscription(state, subscription_id)

    cond do
      # If subscription doesn't exist, return error
      is_nil(subscription) ->
        {:reply,
         {:error,
          Error.validation_error("Subscription does not exist", %{
            subscription_id: subscription_id
          })}, state}

      # If subscription is not persistent, return error
      not subscription.persistent? ->
        {:reply,
         {:error,
          Error.validation_error("Subscription is not persistent", %{
            subscription_id: subscription_id
          })}, state}

      # Otherwise, acknowledge the signal
      true ->
        # In a real implementation, this would update the checkpoint for the subscription
        {:reply, :ok, state}
    end
  end

  def handle_call({:reconnect, subscriber_id, client_pid}, _from, state) do
    case BusState.get_subscription(state, subscriber_id) do
      nil ->
        {:reply, {:error, :subscription_not_found}, state}

      subscription ->
        if subscription.persistent? do
          # Update the client PID in the subscription
          updated_subscription = %{
            subscription
            | dispatch: {:pid, [delivery_mode: :async, target: client_pid]}
          }

          case BusState.add_subscription(state, subscriber_id, updated_subscription) do
            {:error, :subscription_exists} ->
              # If subscription already exists, notify the persistence process and get latest timestamp
              GenServer.cast(subscription.persistence_pid, {:reconnect, client_pid})

              latest_timestamp =
                state.log
                |> Map.values()
                |> Enum.map(& &1.time)
                |> Enum.max(fn -> 0 end)

              {:reply, {:ok, latest_timestamp}, state}

            {:ok, updated_state} ->
              # Notify the persistence process and get latest timestamp
              GenServer.cast(subscription.persistence_pid, {:reconnect, client_pid})

              latest_timestamp =
                updated_state.log
                |> Map.values()
                |> Enum.map(& &1.time)
                |> Enum.max(fn -> 0 end)

              {:reply, {:ok, latest_timestamp}, updated_state}
          end
        else
          # For non-persistent subscriptions, just update the client PID
          updated_subscription = %{
            subscription
            | dispatch: {:pid, [delivery_mode: :async, target: client_pid]}
          }

          case BusState.add_subscription(state, subscriber_id, updated_subscription) do
            {:error, :subscription_exists} ->
              # If subscription already exists, just get the latest timestamp
              latest_timestamp =
                state.log
                |> Map.values()
                |> Enum.map(& &1.time)
                |> Enum.max(fn -> 0 end)

              {:reply, {:ok, latest_timestamp}, state}

            {:ok, updated_state} ->
              # Get the latest signal timestamp from the log
              latest_timestamp =
                updated_state.log
                |> Map.values()
                |> Enum.map(& &1.time)
                |> Enum.max(fn -> 0 end)

              {:reply, {:ok, latest_timestamp}, updated_state}
          end
        end
    end
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    dbug("handle_info :DOWN", pid: pid, reason: reason, state: state)
    # Remove the subscriber if it dies
    case Enum.find(state.subscribers, fn {_id, sub_pid} -> sub_pid == pid end) do
      nil ->
        {:noreply, state}

      {subscriber_id, _} ->
        Logger.info("Subscriber #{subscriber_id} terminated with reason: #{inspect(reason)}")
        {_, new_subscribers} = Map.pop(state.subscribers, subscriber_id)
        {:noreply, %{state | subscribers: new_subscribers}}
    end
  end

  def handle_info(msg, state) do
    dbug("handle_info", msg: msg, state: state)
    Logger.debug("Unexpected message in Bus: #{inspect(msg)}")
    {:noreply, state}
  end
end
