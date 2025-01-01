# defmodule Jido.SignalStore.TelemetryTest do
#   use ExUnit.Case

#   alias Jido.DefaultApp
#   alias Jido.SignalStore
#   alias Jido.SignalStore.EventData
#   alias Jido.SignalStore.RecordedEvent
#   alias Jido.SignalStore.SnapshotData
#   alias Jido.Middleware.Commands.IncrementCount
#   alias Jido.Middleware.Commands.RaiseError

#   setup do
#     start_supervised!(DefaultApp)
#     attach_telemetry()

#     :ok
#   end

#   defmodule TestRouter do
#     use Jido.Commands.Router

#     alias Jido.Middleware.Commands.CommandHandler
#     alias Jido.Middleware.Commands.CounterAggregateRoot

#     dispatch(IncrementCount,
#       to: CommandHandler,
#       aggregate: CounterAggregateRoot,
#       identity: :aggregate_uuid
#     )

#     dispatch(RaiseError,
#       to: CommandHandler,
#       aggregate: CounterAggregateRoot,
#       identity: :aggregate_uuid
#     )
#   end

#   describe "snapshotting telemetry events" do
#     test "emit `[:jido, :event_store, :record_snapshot, :start | :stop]` event" do
#       snapshot = %SnapshotData{}
#       assert :ok = SignalStore.record_snapshot(DefaultApp, snapshot)

#       assert_receive {[:jido, :event_store, :record_snapshot, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :record_snapshot, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, snapshot: ^snapshot} = meta
#     end

#     test "emit `[:jido, :event_store, :read_snapshot, :start | :stop]` event" do
#       uuid = UUID.uuid4()
#       assert {:error, :snapshot_not_found} = SignalStore.read_snapshot(DefaultApp, uuid)

#       assert_receive {[:jido, :event_store, :read_snapshot, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :read_snapshot, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, source_uuid: ^uuid} = meta
#     end

#     test "emit `[:jido, :event_store, :delete_snapshot, :start | :stop]` event" do
#       uuid = UUID.uuid4()
#       assert :ok = SignalStore.delete_snapshot(DefaultApp, uuid)

#       assert_receive {[:jido, :event_store, :delete_snapshot, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :delete_snapshot, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, source_uuid: ^uuid} = meta
#     end
#   end

#   describe "streaming telemetry events" do
#     test "emit `[:jido, :event_store, :stream_forward, :start | :stop]` event" do
#       uuid = UUID.uuid4()
#       assert {:error, :stream_not_found} = SignalStore.stream_forward(DefaultApp, uuid)

#       assert_receive {[:jido, :event_store, :stream_forward, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :stream_forward, :stop], 2, _meas, meta}

#       assert %{
#                application: DefaultApp,
#                stream_uuid: ^uuid,
#                start_version: 0,
#                read_batch_size: 1_000
#              } = meta
#     end
#   end

#   describe "ack_event telemetry events" do
#     test "emit `[:jido, :event_store, :ack_event, :start | :stop]` event" do
#       pid = self()
#       event = %RecordedEvent{}
#       assert :ok = SignalStore.ack_event(DefaultApp, pid, event)

#       assert_receive {[:jido, :event_store, :ack_event, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :ack_event, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, subscription: ^pid, event: ^event} = meta
#     end
#   end

#   describe "append_to_stream telemetry events" do
#     test "emit `[:jido, :event_store, :append_to_stream, :start | :stop]` event" do
#       uuid = UUID.uuid4()
#       assert :ok = SignalStore.append_to_stream(DefaultApp, uuid, 0, [%EventData{}])

#       assert_receive {[:jido, :event_store, :append_to_stream, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :append_to_stream, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, expected_version: 0, stream_uuid: ^uuid} = meta
#     end
#   end

#   describe "subscription telemetry events" do
#     test "emit `[:jido, :event_store, :subscribe, :start | :stop]` event" do
#       uuid = UUID.uuid4()
#       assert :ok = SignalStore.subscribe(DefaultApp, uuid)

#       assert_receive {[:jido, :event_store, :subscribe, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :subscribe, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, stream_uuid: ^uuid} = meta
#     end

#     test "emit `[:jido, :event_store, :subscribe_to, :start | :stop]` event" do
#       subscriber = self()
#       assert {:ok, pid} = SignalStore.subscribe_to(DefaultApp, :all, "Test", subscriber, :current)

#       assert_receive {:subscribed, ^pid}
#       assert_receive {[:jido, :event_store, :subscribe_to, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :subscribe_to, :stop], 2, _meas, meta}

#       assert %{
#                application: DefaultApp,
#                stream_uuid: :all,
#                subscription_name: "Test",
#                subscriber: ^subscriber,
#                start_from: :current
#              } = meta
#     end

#     test "emit `[:jido, :event_store, :unsubscribe, :start | :stop]` event" do
#       assert {:ok, pid} = SignalStore.subscribe_to(DefaultApp, :all, "Test", self(), :current)

#       assert_receive {:subscribed, ^pid}

#       assert_receive {[:jido, :event_store, :subscribe_to, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :subscribe_to, :stop], 2, _meas, _meta}

#       assert :ok = SignalStore.unsubscribe(DefaultApp, pid)

#       assert_receive {[:jido, :event_store, :unsubscribe, :start], 3, _meas, _meta}
#       assert_receive {[:jido, :event_store, :unsubscribe, :stop], 4, _meas, meta}
#       assert %{application: DefaultApp, subscription: ^pid} = meta
#     end

#     test "emit `[:jido, :event_store, :delete_subscription, :start | :stop]` event" do
#       assert {:error, :subscription_not_found} =
#                SignalStore.delete_subscription(DefaultApp, :all, "Test")

#       assert_receive {[:jido, :event_store, :delete_subscription, :start], 1, _meas, _meta}
#       assert_receive {[:jido, :event_store, :delete_subscription, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, subscribe_to: :all, handler_name: "Test"} = meta
#     end
#   end

#   defp attach_telemetry do
#     agent = start_supervised!({Agent, fn -> 1 end})
#     handler = :"#{__MODULE__}-handler"

#     events = [
#       :ack_event,
#       :append_to_stream,
#       :delete_snapshot,
#       :delete_subscription,
#       :record_snapshot,
#       :read_snapshot,
#       :stream_forward,
#       :subscribe,
#       :subscribe_to,
#       :unsubscribe
#     ]

#     :telemetry.attach_many(
#       handler,
#       Enum.flat_map(events, fn event ->
#         [
#           [:jido, :event_store, event, :start],
#           [:jido, :event_store, event, :stop]
#         ]
#       end),
#       fn event_name, measurements, metadata, reply_to ->
#         num = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
#         send(reply_to, {event_name, num, measurements, metadata})
#       end,
#       self()
#     )

#     on_exit(fn ->
#       :telemetry.detach(handler)
#     end)
#   end
# end
