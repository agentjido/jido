defmodule Jido.Signal.Bus.Subscriptions.Subscriber do
  @moduledoc false

  alias Jido.Signal.Router
  alias Jido.Signal.Router.Index
  alias Jido.Signal.Telemetry

  @enforce_keys [:id, :path, :durable?, :cursor, :created_at]
  defstruct [
    :id,
    :path,
    :target,
    :monitor_ref,
    :in_flight,
    :created_at,
    durable?: false,
    cursor: 0
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          path: String.t(),
          durable?: boolean(),
          target: pid() | nil,
          monitor_ref: reference() | nil,
          cursor: non_neg_integer(),
          in_flight: pos_integer() | nil,
          created_at: String.t()
        }

  @doc false
  @spec monitor_target(map(), String.t(), pid()) :: {reference(), map()}
  def monitor_target(state, subscription_id, target) do
    monitor_ref = Process.monitor(target)
    {monitor_ref, %{state | monitors: Map.put(state.monitors, monitor_ref, subscription_id)}}
  end

  @doc false
  @spec demonitor_target(map(), t()) :: map()
  def demonitor_target(state, %__MODULE__{monitor_ref: nil}), do: state

  def demonitor_target(state, %__MODULE__{monitor_ref: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    %{state | monitors: Map.delete(state.monitors, monitor_ref)}
  end

  @doc false
  @spec insert_subscriber(map(), t(), Router.match() | nil) :: map()
  def insert_subscriber(state, subscriber, match \\ nil) do
    route =
      case match do
        nil -> {subscriber.path, subscriber.id}
        match -> {subscriber.path, match, subscriber.id}
      end

    {:ok, router} = Router.add(state.router, route)

    %{
      state
      | subscriptions: Map.put(state.subscriptions, subscriber.id, subscriber),
        router: router
    }
  end

  @doc false
  @spec put_subscriber(map(), t()) :: map()
  def put_subscriber(state, subscriber) do
    %{state | subscriptions: Map.put(state.subscriptions, subscriber.id, subscriber)}
  end

  @doc false
  @spec remove_subscriber(map(), t(), boolean()) :: map()
  def remove_subscriber(state, subscriber, demonitor? \\ true) do
    state = if demonitor?, do: demonitor_target(state, subscriber), else: state
    if is_pid(subscriber.target), do: emit_subscription(:detached, state, subscriber)

    %{
      state
      | subscriptions: Map.delete(state.subscriptions, subscriber.id),
        router: Index.remove_target(state.router, subscriber.path, subscriber.id)
    }
  end

  @doc false
  @spec emit_subscription(atom(), map(), t()) :: :ok
  def emit_subscription(event, state, subscriber) do
    Telemetry.execute(
      [:jido, :signal, :bus, :subscription, event],
      %{system_time: System.system_time()},
      metadata(state, subscriber)
    )
  end

  @doc false
  @spec emit_delivery(map(), t(), Jido.Signal.t(), pos_integer() | nil) :: :ok
  def emit_delivery(state, subscriber, signal, cursor \\ nil) do
    Telemetry.execute(
      [:jido, :signal, :bus, :deliver],
      %{system_time: System.system_time()},
      Map.merge(metadata(state, subscriber), %{
        cursor: cursor,
        signal_id: signal.id,
        signal_type: signal.type
      }),
      signal
    )
  end

  defp metadata(state, subscriber) do
    %{
      bus_name: state.name,
      bus_jido: state.jido,
      bus_registry: state.registry,
      subscription_id: subscriber.id,
      subscription_path: subscriber.path,
      durable: subscriber.durable?
    }
  end
end
