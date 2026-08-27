# defmodule Jido.Sensors.Bus do
#   @moduledoc """
#   A sensor that monitors signals on a bus and emits them as signals.

#   This sensor subscribes to a bus and forwards signals received on that bus to its configured target.
#   It filters signals based on the required stream ID.

#   ## Options

#     * `:id` - Required. The unique identifier for this sensor instance
#     * `:target` - Required. The target to dispatch signals to
#     * `:bus_name` - Required. The name of the bus to monitor
#     * `:stream_id` - Required. The specific stream ID to monitor.
#   """

#   use Jido.Sensor,
#     name: "bus_sensor",
#     description: "Monitors signals on a bus",
#     category: :system,
#     tags: [:bus, :monitoring],
#     vsn: "1.0.0",
#     schema: Zoi.object(%{
#       bus_name: Zoi.atom(description: "Name of the bus to monitor"),
#       stream_id: Zoi.string(description: "Stream ID to monitor"),
#       filter_source:
#         Zoi.string(description: "Optional source ID to filter out") |> Zoi.optional()
#     })

#   require Logger

#   @impl true
#   def mount(opts) do
#     target =
#       case opts.target do
#         {:pid, target_opts} when is_list(target_opts) ->
#           {:pid,
#            Keyword.merge(target_opts,
#              message_format: fn signal -> {:signal, {:ok, signal}} end
#            )}

#         {:pid, pid} when is_pid(pid) ->
#           {:pid,
#            [
#              target: pid,
#              delivery_mode: :async,
#              message_format: fn signal -> {:signal, {:ok, signal}} end
#            ]}

#         _ ->
#           opts.target
#       end

#     state = %{
#       id: opts.id,
#       target: target,
#       sensor: %{name: "bus_sensor"},
#       config: %{
#         bus_name: opts.bus_name,
#         stream_id: opts.stream_id,
#         filter_source: Map.get(opts, :filter_source)
#       }
#     }

#     # Subscribe to the bus
#     case subscribe_to_bus(state) do
#       {:ok, subscription} ->
#         {:ok, Map.put(state, :subscription, subscription)}

#       {:error, reason} = error ->
#         Logger.error("Failed to subscribe to bus: #{inspect(reason)}")
#         error
#     end
#   end

#   @impl true
#   def handle_info({:subscribed, subscription}, state) do
#     case Jido.Signal.Dispatch.dispatch(
#            {:subscribed, subscription},
#            {:pid,
#             [
#               target: extract_target_pid(state.target),
#               delivery_mode: :async,
#               message_format: fn _ -> {:subscribed, subscription} end
#             ]}
#          ) do
#       :ok ->
#         {:noreply, %{state | subscription: subscription}}

#       {:error, reason} ->
#         Logger.error("Failed to forward subscription message: #{inspect(reason)}")
#         {:noreply, state}
#     end
#   end

#   def handle_info({:signals, signals}, state) when is_list(signals) do
#     handle_signals(signals, state)
#   end

#   def handle_info({:signals, _subscription_ref, signals}, state) when is_list(signals) do
#     handle_signals(signals, state)
#   end

#   def handle_info(msg, state) do
#     Logger.warning("#{__MODULE__} received unexpected message: #{inspect(msg)}")
#     {:noreply, state}
#   end

#   @impl true
#   def deliver_signal(_state) do
#     {:ok, nil}
#   end

#   @impl true
#   def shutdown(state) do
#     if subscription = Map.get(state, :subscription) do
#       case Jido.Bus.whereis(state.config.bus_name) do
#         {:ok, bus} ->
#           Jido.Bus.unsubscribe(bus, subscription)

#         _error ->
#           :ok
#       end
#     end

#     :ok
#   end

#   # Private helpers

#   defp subscribe_to_bus(%{config: config, id: id}) do
#     stream = Map.get(config, :stream_id, :all)

#     case Jido.Bus.whereis(config.bus_name) do
#       {:ok, bus} ->
#         Jido.Bus.subscribe(
#           bus,
#           stream,
#           "#{id}_subscription",
#           self(),
#           start_from: :origin
#         )

#       error ->
#         error
#     end
#   end

#   defp handle_signals(signals, state) do
#     Logger.debug("Received signals: #{inspect(signals)}")
#     filtered = Enum.filter(signals, &matches_stream?(&1, Map.get(state.config, :stream_id)))
#     Logger.debug("Filtered signals: #{inspect(filtered)}")

#     case filtered do
#       [] ->
#         {:noreply, state}

#       signals ->
#         Enum.each(signals, fn signal ->
#           Logger.debug("Converting signal: #{inspect(signal)}")

#           case convert_signal(signal, state) do
#             {:ok, converted} ->
#               Logger.debug("Converted signal: #{inspect(converted)}")
#               Logger.debug("Target: #{inspect(state.target)}")

#               case state.target do
#                 {:pid, target_opts} when is_list(target_opts) ->
#                   message_format =
#                     Keyword.get(target_opts, :message_format, fn s -> {:signal, {:ok, s}} end)

#                   target_pid = Keyword.get(target_opts, :target)
#                   send(target_pid, message_format.(converted))

#                 {:pid, pid} when is_pid(pid) ->
#                   send(pid, {:signal, {:ok, converted}})

#                 _ ->
#                   case Jido.Signal.Dispatch.dispatch(
#                          converted,
#                          state.target
#                        ) do
#                     :ok ->
#                       Logger.debug("Successfully dispatched signal")

#                     error ->
#                       Logger.error("Failed to dispatch signal: #{inspect(error)}")
#                   end
#               end

#             error ->
#               Logger.error("Failed to convert signal: #{inspect(error)}")
#           end
#         end)

#         {:noreply, state}
#     end
#   end

#   defp matches_stream?(_signal, nil), do: true

#   defp matches_stream?(%Jido.Bus.RecordedSignal{} = signal, stream_id) do
#     signal.stream_id == stream_id
#   end

#   defp matches_stream?(%Jido.Signal{} = signal, stream_id) do
#     get_in(signal.jido_metadata || %{}, ["stream_id"]) == stream_id
#   end

#   defp convert_signal(%Jido.Bus.RecordedSignal{} = recorded, state) do
#     case Jido.Signal.new(%{
#            source: "#{state.sensor.name}:#{state.id}",
#            type: recorded.type,
#            data: recorded.data,
#            jido_metadata:
#              Map.merge(recorded.jido_metadata || %{}, %{
#                "original_id" => recorded.signal_id,
#                "original_stream" => recorded.stream_id,
#                "original_version" => recorded.stream_version,
#                "original_source" => recorded.causation_id,
#                "original_correlation" => recorded.correlation_id
#              })
#          }) do
#       {:ok, signal} -> {:ok, signal}
#       error -> error
#     end
#   end

#   defp convert_signal(%Jido.Signal{} = signal, state) do
#     Logger.debug("Converting Jido.Signal: #{inspect(signal)}")

#     {:ok,
#      %{
#        signal
#        | source: "#{state.sensor.name}:#{state.id}",
#          jido_metadata:
#            Map.merge(signal.jido_metadata || %{}, %{
#              "original_id" => signal.id,
#              "original_stream" => get_in(signal.jido_metadata || %{}, ["stream_id"]),
#              "original_source" => signal.source
#            })
#      }}
#   end

#   defp extract_target_pid({:pid, opts}) when is_list(opts), do: Keyword.get(opts, :target)
#   defp extract_target_pid(pid) when is_pid(pid), do: pid
#   defp extract_target_pid(_), do: nil
# end
