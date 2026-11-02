defmodule Jido.Signal.Bus.Subscriptions.Runtime do
  @moduledoc false

  alias Jido.Signal.Bus.Subscriptions.Subscriber
  alias Jido.Signal.Router.Index
  alias Jido.Signal.Telemetry

  @doc false
  @spec monitor_target(map(), String.t(), pid()) :: {reference(), map()}
  def monitor_target(state, subscription_id, target) do
    monitor_ref = Process.monitor(target)
    {monitor_ref, %{state | monitors: Map.put(state.monitors, monitor_ref, subscription_id)}}
  end

  @doc false
  @spec demonitor_target(map(), Subscriber.t()) :: map()
  def demonitor_target(state, %Subscriber{monitor_ref: nil}), do: state

  def demonitor_target(state, %Subscriber{monitor_ref: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    %{state | monitors: Map.delete(state.monitors, monitor_ref)}
  end

  @doc false
  @spec remove_subscriber(map(), Subscriber.t(), boolean()) :: map()
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
  @spec deliver(map(), Subscriber.t(), term(), Jido.Signal.t(), pos_integer() | nil) :: :ok
  def deliver(state, subscriber, message, signal, cursor \\ nil) do
    send(subscriber.target, message)
    emit_delivery(state, subscriber, signal, cursor)
  end

  @doc false
  @spec emit_subscription(atom(), map(), Subscriber.t()) :: :ok
  def emit_subscription(event, state, subscriber) do
    Telemetry.execute(
      [:jido, :signal, :bus, :subscription, event],
      %{system_time: System.system_time()},
      metadata(state, subscriber)
    )
  end

  defp emit_delivery(state, subscriber, signal, cursor) do
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
