defmodule Jido.Bus do
  @moduledoc """
  Use the signal store configured for a Commanded application.

  ### Telemetry Signals

  Adds telemetry signals for the following functions. Signals are emitted in the form

  `[:jido, :bus, signal]` with their spannable postfixes (`start`, `stop`, `exception`)

    * ack/3
    * adapter/2
    * publish/4
    * delete_snapshot/2
    * unsubscribe/3
    * read_snapshot/2
    * record_snapshot/2
    * replay/2
    * replay/3
    * replay/4
    * subscribe/2
    * subscribe_persistent/5
    * subscribe_persistent/6
    * unsubscribe/2

  """
  use GenServer
  require Logger

  use TypedStruct

  typedstruct do
    field(:id, String.t(), default: UUID.uuid4())
    field(:name, atom())
    field(:adapter, module())
    field(:adapter_meta, map())
    field(:config, Keyword.t(), default: [])
  end

  @type start_option ::
          {:name, atom()}
          | {:adapter, :pubsub | :in_memory | module()}
          | {:pubsub_name, atom()}
          | {atom(), term()}

  # Client API

  @doc """
  Start a bus as part of a supervision tree.

  ## Options

    * `:name` - Required. The name to register the bus process under
    * `:adapter` - The adapter type. Either `:pubsub`, `:in_memory`, or a custom module
    * Other options are passed to the chosen adapter

  ## Examples

      children = [
        {Jido.Bus, name: :jido_agent_123, adapter: :pubsub, pubsub_name: MyApp.PubSub}
      ]
  """
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @doc """
  Start a bus process.

  See `child_spec/1` for options.
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    adapter = Keyword.get(opts, :adapter, :in_memory)
    GenServer.start_link(__MODULE__, {name, adapter, opts}, name: via_tuple(name, opts))
  end

  @doc """
  Returns a via tuple for addressing the bus process.

  ## Options
    * `:registry` - The registry to use (defaults to Jido.BusRegistry)

  ## Examples
      iex> Jido.Bus.via_tuple(:my_bus)
      {:via, Registry, {Jido.BusRegistry, :my_bus}}

      iex> Jido.Bus.via_tuple(:my_bus, registry: MyApp.Registry)
      {:via, Registry, {MyApp.Registry, :my_bus}}
  """
  def via_tuple(name, opts \\ []) do
    registry = Keyword.get(opts, :registry, Jido.BusRegistry)
    {:via, Registry, {registry, name}}
  end

  @doc """
  Gets the PID of a running bus by name.

  Returns `{:ok, pid}` if found, `{:error, :not_found}` otherwise.
  """
  def whereis(name, opts \\ []) do
    registry = Keyword.get(opts, :registry, Jido.BusRegistry)

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Append one or more signals to a stream atomically.
  """
  def publish(name, stream_id, expected_version, signals, opts \\ []) do
    GenServer.call(via_tuple(name), {:publish, stream_id, expected_version, signals, opts})
  end

  @doc """
  Streams signals from the given stream, in the order in which they were originally written.
  """
  def replay(name, stream_id, start_version \\ 0, read_batch_size \\ 1_000) do
    GenServer.call(via_tuple(name), {:replay, stream_id, start_version, read_batch_size})
  end

  @doc """
  Create a transient subscription to a single signal stream.
  """
  def subscribe(name, stream_id) do
    GenServer.call(via_tuple(name), {:subscribe, stream_id})
  end

  @doc """
  Create a persistent subscription to an signal stream.
  """
  def subscribe_persistent(name, stream_id, subscription_name, subscriber, start_from, opts \\ []) do
    GenServer.call(
      via_tuple(name),
      {:subscribe_persistent, stream_id, subscription_name, subscriber, start_from, opts}
    )
  end

  @doc """
  Acknowledge receipt and successful processing of a signal.
  """
  def ack(name, subscription, signal) do
    GenServer.call(via_tuple(name), {:ack, subscription, signal})
  end

  @doc """
  Unsubscribe an existing subscriber from signal notifications.
  """
  def unsubscribe(name, subscription) do
    GenServer.call(via_tuple(name), {:unsubscribe, subscription})
  end

  @doc """
  Delete an existing subscription.
  """
  def unsubscribe(name, subscribe_persistent, handler_name) do
    GenServer.call(via_tuple(name), {:unsubscribe, subscribe_persistent, handler_name})
  end

  @doc """
  Read a snapshot, if available, for a given source.
  """
  def read_snapshot(name, source_id) do
    GenServer.call(via_tuple(name), {:read_snapshot, source_id})
  end

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  def record_snapshot(name, snapshot) do
    GenServer.call(via_tuple(name), {:record_snapshot, snapshot})
  end

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  def delete_snapshot(name, source_id) do
    GenServer.call(via_tuple(name), {:delete_snapshot, source_id})
  end

  # Server Callbacks

  @impl GenServer
  def init({name, adapter_type, opts}) do
    adapter = resolve_adapter(adapter_type)

    with {:ok, children, adapter_meta} <- adapter.child_spec(name, opts) do
      results =
        Enum.map(children, fn child ->
          DynamicSupervisor.start_child(Jido.BusSupervisor, child)
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil ->
          state = %__MODULE__{
            name: name,
            adapter: adapter,
            adapter_meta: adapter_meta,
            config: opts
          }

          {:ok, state}

        {:error, reason} ->
          {:stop, reason}
      end
    end
  end

  @impl GenServer
  def handle_call({:publish, stream_id, expected_version, signals, opts}, _from, state) do
    meta = %{bus: state, stream_id: stream_id, expected_version: expected_version}

    result =
      span(:publish, meta, fn ->
        if function_exported?(state.adapter, :publish, 5) do
          state.adapter.publish(state, stream_id, expected_version, signals, opts)
        else
          state.adapter.publish(state, stream_id, expected_version, signals)
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:replay, stream_id, start_version, read_batch_size}, _from, state) do
    meta = %{
      bus: state,
      stream_id: stream_id,
      start_version: start_version,
      read_batch_size: read_batch_size
    }

    result =
      span(:replay, meta, fn ->
        case state.adapter.replay(state, stream_id, start_version, read_batch_size) do
          {:error, _error} = error -> error
          stream -> stream
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:subscribe, stream_id}, _from, state) do
    result =
      span(:subscribe, %{bus: state, stream_id: stream_id}, fn ->
        state.adapter.subscribe(state, stream_id)
      end)

    {:reply, result, state}
  end

  def handle_call(
        {:subscribe_persistent, stream_id, subscription_name, subscriber, start_from, opts},
        _from,
        state
      ) do
    meta = %{
      bus: state,
      stream_id: stream_id,
      subscription_name: subscription_name,
      subscriber: subscriber,
      start_from: start_from
    }

    result =
      span(:subscribe_persistent, meta, fn ->
        if function_exported?(state.adapter, :subscribe_persistent, 6) do
          state.adapter.subscribe_persistent(
            state,
            stream_id,
            subscription_name,
            subscriber,
            start_from,
            opts
          )
        else
          state.adapter.subscribe_persistent(
            state,
            stream_id,
            subscription_name,
            subscriber,
            start_from
          )
        end
      end)

    {:reply, result, state}
  end

  def handle_call({:ack, subscription, signal}, _from, state) do
    result =
      span(:ack, %{bus: state, subscription: subscription, signal: signal}, fn ->
        state.adapter.ack(state, subscription, signal)
      end)

    {:reply, result, state}
  end

  def handle_call({:unsubscribe, subscription}, _from, state) do
    result =
      span(:unsubscribe, %{bus: state, subscription: subscription}, fn ->
        state.adapter.unsubscribe(state, subscription)
      end)

    {:reply, result, state}
  end

  def handle_call({:unsubscribe, subscribe_persistent, handler_name}, _from, state) do
    meta = %{bus: state, subscribe_persistent: subscribe_persistent, handler_name: handler_name}

    result =
      span(:unsubscribe, meta, fn ->
        state.adapter.unsubscribe(state, subscribe_persistent, handler_name)
      end)

    {:reply, result, state}
  end

  def handle_call({:read_snapshot, source_id}, _from, state) do
    result =
      span(:read_snapshot, %{bus: state, source_id: source_id}, fn ->
        state.adapter.read_snapshot(state, source_id)
      end)

    {:reply, result, state}
  end

  def handle_call({:record_snapshot, snapshot}, _from, state) do
    result =
      span(:record_snapshot, %{bus: state, snapshot: snapshot}, fn ->
        state.adapter.record_snapshot(state, snapshot)
      end)

    {:reply, result, state}
  end

  def handle_call({:delete_snapshot, source_id}, _from, state) do
    result =
      span(:delete_snapshot, %{bus: state, source_id: source_id}, fn ->
        state.adapter.delete_snapshot(state, source_id)
      end)

    {:reply, result, state}
  end

  defp span(signal, meta, func) do
    :telemetry.span([:jido, :bus, signal], meta, fn ->
      {func.(), meta}
    end)
  end

  defp resolve_adapter(:in_memory), do: Jido.Bus.Adapters.InMemory
  defp resolve_adapter(:pubsub), do: Jido.Bus.Adapters.PubSub
  defp resolve_adapter(adapter) when is_atom(adapter), do: adapter
end
