# defmodule Jido.Sensors.Bus do
#   @moduledoc """
#   A sensor that subscribes to a Jido.Bus and emits signals based on bus events.
#   """
#   use Jido.Sensor,
#     name: "bus_sensor",
#     description: "Monitors events from a Jido.Bus instance",
#     category: :bus,
#     tags: [:bus, :events],
#     vsn: "1.0.0",
#     schema: [
#       bus_name: [type: :atom, required: true],
#       stream_id: [type: :string, required: true],
#       subscription_name: [type: :string, required: true],
#       concurrency: [type: :integer, default: 1],
#       partition_by: [type: :any, default: nil]
#     ]

#   require Logger

#   @impl true
#   def mount(opts) do
#     subscription_opts = [
#       concurrency_limit: opts.concurrency,
#       partition_by: opts.partition_by
#     ]

#     with {:ok, subscription} <-
#            Jido.Bus.subscribe_persistent(
#              opts.bus_name,
#              opts.stream_id,
#              opts.subscription_name,
#              self(),
#              :origin,
#              subscription_opts
#            ) do
#       state = Map.put(opts, :subscription, subscription)
#       {:ok, state}
#     end
#   end

#   @impl true
#   def handle_info({:signal, signal}, state) do
#     case generate_signal(state, signal) do
#       {:ok, sensor_signal} ->
#         publish_signal(sensor_signal, state)
#         # Acknowledge the signal after successful processing
#         :ok = Jido.Bus.ack(state.bus_name, state.subscription, signal)
#         {:noreply, state}

#       {:error, reason} ->
#         Logger.warning("Error generating signal: #{inspect(reason)}")
#         {:noreply, state}
#     end
#   end

#   @impl true
#   def generate_signal(state, bus_signal) do
#     {:ok,
#      Jido.Signal.new(%{
#        source: "#{state.sensor.name}:#{state.id}",
#        subject: "bus_event",
#        type: "bus",
#        data: %{
#          stream_id: state.stream_id,
#          signal: bus_signal
#        },
#        timestamp: DateTime.utc_now()
#      })}
#   end

#   @impl true
#   def shutdown(state) do
#     :ok = Jido.Bus.unsubscribe(state.bus_name, state.subscription)
#     {:ok, state}
#   end
# end
