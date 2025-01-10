# defmodule Jido.Bus.TelemetryTest do
#   use ExUnit.Case

#   alias Commanded.DefaultApp
#   alias Jido.Bus
#   alias Jido.Bus.Signal
#   alias Jido.Bus.RecordedSignal
#   alias Jido.Bus.Snapshot
#   alias Commanded.Middleware.Commands.IncrementCount
#   alias Commanded.Middleware.Commands.RaiseError
#   alias Commanded.UUID

#   setup do
#     start_supervised!(DefaultApp)
#     attach_telemetry()

#     :ok
#   end

#   defmodule TestRouter do
#     use Commanded.Commands.Router

#     alias Commanded.Middleware.Commands.CommandHandler
#     alias Commanded.Middleware.Commands.CounterAggregateRoot

#     dispatch IncrementCount,
#       to: CommandHandler,
#       aggregate: CounterAggregateRoot,
#       identity: :aggregate_uuid

#     dispatch RaiseError,
#       to: CommandHandler,
#       aggregate: CounterAggregateRoot,
#       identity: :aggregate_uuid
#   end

#   describe "snapshotting telemetry signals" do
#     test "emit `[:commanded, :signal_store, :record_snapshot, :start | :stop]` signal" do
#       snapshot = %Snapshot{}
#       assert :ok = Bus.record_snapshot(DefaultApp, snapshot)

#       assert_receive {[:commanded, :signal_store, :record_snapshot, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :record_snapshot, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, snapshot: ^snapshot} = meta
#     end

#     test "emit `[:commanded, :signal_store, :read_snapshot, :start | :stop]` signal" do
#       uuid = UUID.uuid4()
#       assert {:error, :snapshot_not_found} = Bus.read_snapshot(DefaultApp, uuid)

#       assert_receive {[:commanded, :signal_store, :read_snapshot, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :read_snapshot, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, source_id: ^uuid} = meta
#     end

#     test "emit `[:commanded, :signal_store, :delete_snapshot, :start | :stop]` signal" do
#       uuid = UUID.uuid4()
#       assert :ok = Bus.delete_snapshot(DefaultApp, uuid)

#       assert_receive {[:commanded, :signal_store, :delete_snapshot, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :delete_snapshot, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, source_id: ^uuid} = meta
#     end
#   end

#   describe "streaming telemetry signals" do
#     test "emit `[:commanded, :signal_store, :replay, :start | :stop]` signal" do
#       uuid = UUID.uuid4()
#       assert {:error, :stream_not_found} = Bus.replay(DefaultApp, uuid)

#       assert_receive {[:commanded, :signal_store, :replay, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :replay, :stop], 2, _meas, meta}

#       assert %{
#                application: DefaultApp,
#                stream_id: ^uuid,
#                start_version: 0,
#                read_batch_size: 1_000
#              } = meta
#     end
#   end

#   describe "ack telemetry signals" do
#     test "emit `[:commanded, :signal_store, :ack, :start | :stop]` signal" do
#       pid = self()
#       signal = %RecordedSignal{}
#       assert :ok = Bus.ack(DefaultApp, pid, signal)

#       assert_receive {[:commanded, :signal_store, :ack, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :ack, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, subscription: ^pid, signal: ^signal} = meta
#     end
#   end

#   describe "publish telemetry signals" do
#     test "emit `[:commanded, :signal_store, :publish, :start | :stop]` signal" do
#       uuid = UUID.uuid4()
#       assert :ok = Bus.publish(DefaultApp, uuid, 0, [%Signal{}])

#       assert_receive {[:commanded, :signal_store, :publish, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :publish, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, expected_version: 0, stream_id: ^uuid} = meta
#     end
#   end

#   describe "subscription telemetry signals" do
#     test "emit `[:commanded, :signal_store, :subscribe, :start | :stop]` signal" do
#       uuid = UUID.uuid4()
#       assert :ok = Bus.subscribe(DefaultApp, uuid)

#       assert_receive {[:commanded, :signal_store, :subscribe, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :subscribe, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, stream_id: ^uuid} = meta
#     end

#     test "emit `[:commanded, :signal_store, :subscribe_persistent, :start | :stop]` signal" do
#       subscriber = self()
#       assert {:ok, pid} = Bus.subscribe_persistent(DefaultApp, :all, "Test", subscriber, :current)

#       assert_receive {:subscribed, ^pid}
#       assert_receive {[:commanded, :signal_store, :subscribe_persistent, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :subscribe_persistent, :stop], 2, _meas, meta}

#       assert %{
#                application: DefaultApp,
#                stream_id: :all,
#                subscription_name: "Test",
#                subscriber: ^subscriber,
#                start_from: :current
#              } = meta
#     end

#     test "emit `[:commanded, :signal_store, :unsubscribe, :start | :stop]` signal" do
#       assert {:ok, pid} = Bus.subscribe_persistent(DefaultApp, :all, "Test", self(), :current)

#       assert_receive {:subscribed, ^pid}

#       assert_receive {[:commanded, :signal_store, :subscribe_persistent, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :subscribe_persistent, :stop], 2, _meas, _meta}

#       assert :ok = Bus.unsubscribe(DefaultApp, pid)

#       assert_receive {[:commanded, :signal_store, :unsubscribe, :start], 3, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :unsubscribe, :stop], 4, _meas, meta}
#       assert %{application: DefaultApp, subscription: ^pid} = meta
#     end

#     test "emit `[:commanded, :signal_store, :unsubscribe, :start | :stop]` signal" do
#       assert {:error, :subscription_not_found} =
#                Bus.unsubscribe(DefaultApp, :all, "Test")

#       assert_receive {[:commanded, :signal_store, :unsubscribe, :start], 1, _meas, _meta}
#       assert_receive {[:commanded, :signal_store, :unsubscribe, :stop], 2, _meas, meta}
#       assert %{application: DefaultApp, subscribe_persistent: :all, handler_name: "Test"} = meta
#     end
#   end

#   defp attach_telemetry do
#     agent = start_supervised!({Agent, fn -> 1 end})
#     handler = :"#{__MODULE__}-handler"

#     signals = [
#       :ack,
#       :publish,
#       :delete_snapshot,
#       :unsubscribe,
#       :record_snapshot,
#       :read_snapshot,
#       :replay,
#       :subscribe,
#       :subscribe_persistent,
#       :unsubscribe
#     ]

#     :telemetry.attach_many(
#       handler,
#       Enum.flat_map(signals, fn signal ->
#         [
#           [:commanded, :signal_store, signal, :start],
#           [:commanded, :signal_store, signal, :stop]
#         ]
#       end),
#       fn signal_name, measurements, metadata, reply_to ->
#         num = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
#         send(reply_to, {signal_name, num, measurements, metadata})
#       end,
#       self()
#     )

#     on_exit(fn ->
#       :telemetry.detach(handler)
#     end)
#   end
# end
