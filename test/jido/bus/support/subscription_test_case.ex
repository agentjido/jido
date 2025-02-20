defmodule Jido.Bus.SubscriptionTestCase do
  @moduledoc false
  import JidoTest.SharedTestCase

  define_tests do
    alias Jido.Bus.{RecordedSignal, Subscriber}
    alias Jido.Signal

    defmodule BankAccountOpened do
      @moduledoc false
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    describe "transient subscription to single stream" do
      test "should receive signals appended to the stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        stream_id = Jido.Util.generate_id()

        assert :ok = signal_store.subscribe(signal_store_meta, stream_id)

        :ok = signal_store.publish(signal_store_meta, stream_id, 0, build_signals(1))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 1, from: 1)

        for %RecordedSignal{} = signal <- received_signals do
          assert signal.stream_id == stream_id
          assert %DateTime{} = signal.created_at
        end

        assert Enum.map(received_signals, & &1.stream_version) == [1]

        :ok = signal_store.publish(signal_store_meta, stream_id, 1, build_signals(2))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 2, from: 2)

        for %RecordedSignal{} = signal <- received_signals do
          assert signal.stream_id == stream_id
          assert %DateTime{} = signal.created_at
        end

        assert Enum.map(received_signals, & &1.stream_version) == [2, 3]

        :ok = signal_store.publish(signal_store_meta, stream_id, 3, build_signals(3))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 3, from: 4)

        for %RecordedSignal{} = signal <- received_signals do
          assert signal.stream_id == stream_id
          assert %DateTime{} = signal.created_at
        end

        assert Enum.map(received_signals, & &1.stream_version) == [4, 5, 6]

        refute_receive {:signals, _received_signals}
      end

      test "should not receive signals appended to another stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        stream_id = Jido.Util.generate_id()
        another_stream_id = Jido.Util.generate_id()

        assert :ok = signal_store.subscribe(signal_store_meta, stream_id)

        :ok =
          signal_store.publish(signal_store_meta, another_stream_id, 0, build_signals(1))

        :ok =
          signal_store.publish(signal_store_meta, another_stream_id, 1, build_signals(2))

        refute_receive {:signals, _received_signals}
      end
    end

    describe "transient subscription to all streams" do
      test "should receive signals appended to any stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok = signal_store.subscribe(signal_store_meta, :all)

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 1, from: 1)

        assert Enum.map(received_signals, & &1.stream_id) == ["stream1"]
        assert Enum.map(received_signals, & &1.stream_version) == [1]

        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 2, from: 2)

        assert Enum.map(received_signals, & &1.stream_id) == ["stream2", "stream2"]
        assert Enum.map(received_signals, & &1.stream_version) == [1, 2]

        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 3, from: 4)

        assert Enum.map(received_signals, & &1.stream_id) == ["stream3", "stream3", "stream3"]
        assert Enum.map(received_signals, & &1.stream_version) == [1, 2, 3]

        :ok = signal_store.publish(signal_store_meta, "stream1", 1, build_signals(2))

        received_signals =
          assert_receive_signals(signal_store, signal_store_meta, count: 2, from: 7)

        assert Enum.map(received_signals, & &1.stream_id) == ["stream1", "stream1"]
        assert Enum.map(received_signals, & &1.stream_version) == [2, 3]

        refute_receive {:signals, _received_signals}
      end
    end

    describe "persistent subscription to a single stream" do
      test "should receive `:subscribed` message once subscribed", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            "stream1",
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}
      end

      test "should receive signals appended to stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            "stream1",
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream1", 1, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream1", 3, build_signals(3))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 1, from: 1)
        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 2, from: 2)
        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 3, from: 4)

        refute_receive {:signals, _received_signals}
      end

      test "should not receive signals appended to another stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            "stream1",
            "subscriber",
            self(),
            :origin,
            []
          )

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 1, from: 1)
        refute_receive {:signals, _received_signals}
      end

      test "should skip existing signals when subscribing from current position", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream1", 1, build_signals(2))

        wait_for_signal_store()

        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            "stream1",
            "subscriber",
            self(),
            :current,
            []
          )

        assert_receive {:subscribed, ^subscription}
        refute_receive {:signals, _signals}

        :ok = signal_store.publish(signal_store_meta, "stream1", 3, build_signals(3))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(3))
        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 3, from: 4)
        refute_receive {:signals, _signals}
      end

      test "should receive signals already appended to stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            "stream3",
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 3, from: 1)

        :ok = signal_store.publish(signal_store_meta, "stream3", 3, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream3", 4, build_signals(1))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 2, from: 4)
        refute_receive {:signals, _received_signals}
      end

      test "should prevent duplicate subscriptions for single stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, _subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            "stream1",
            "subscriber",
            self(),
            :origin,
            # Explicitly set limit to 1 for this test
            concurrency_limit: 1
          )

        assert {:error, :subscription_already_exists} ==
                 signal_store.subscribe_persistent(
                   signal_store_meta,
                   "stream1",
                   "subscriber",
                   self(),
                   :origin,
                   # Match the same limit
                   concurrency_limit: 1
                 )
      end
    end

    describe "persistent subscription to all streams" do
      test "should receive `:subscribed` message once subscribed", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}
      end

      test "should receive signals appended to any stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 1, from: 1)
        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 2, from: 2)
        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 3, from: 4)

        refute_receive {:signals, _received_signals}
      end

      test "should receive signals already appended to any stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        wait_for_signal_store()

        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 1, from: 1)
        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 2, from: 2)

        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 3, from: 4)
        refute_receive {:signals, _received_signals}
      end

      test "should skip existing signals when subscribing from current position", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        wait_for_signal_store()

        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :current,
            []
          )

        assert_receive {:subscribed, ^subscription}
        refute_receive {:signals, _received_signals}

        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 3, from: 4)

        refute_receive {:signals, _received_signals}
      end

      test "should prevent duplicate subscriptions for all streams", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, _subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            # Explicitly set limit to 1
            concurrency_limit: 1
          )

        assert {:error, :subscription_already_exists} ==
                 signal_store.subscribe_persistent(
                   signal_store_meta,
                   :all,
                   "subscriber",
                   self(),
                   :origin,
                   # Match the same limit
                   concurrency_limit: 1
                 )
      end
    end

    describe "persistent subscription concurrency" do
      test "should allow multiple subscribers to single subscription", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscriber1} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 2)

        {:ok, subscriber2} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 2)

        assert_receive {:subscribed, ^subscriber1, _subscription1}
        assert_receive {:subscribed, ^subscriber2, _subscription2}
        refute_receive {:subscribed, _subscriber, _subscription}
      end

      test "should enforce concurrency limits for subscriptions", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscriber1} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 1)

        {:ok, subscriber2} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 1)

        assert_receive {:subscribed, ^subscriber1, _subscription1}
        assert_receive {:subscribe_error, :subscription_already_exists, ^subscriber2}
        refute_receive {:subscribed, _subscriber, _subscription}
      end

      test "should distribute signals amongst subscribers", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscriber1} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 3)

        {:ok, subscriber2} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 3)

        {:ok, subscriber3} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 3)

        assert_receive {:subscribed, ^subscriber1, _subscription1}
        assert_receive {:subscribed, ^subscriber2, _subscription2}
        assert_receive {:subscribed, ^subscriber3, _subscription3}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(6))

        subscribers =
          for n <- 1..6 do
            assert_receive {:signals, subscriber, [%RecordedSignal{signal_number: ^n}] = signals}

            :ok = Subscriber.ack(subscriber, signals)

            subscriber
          end
          |> Enum.uniq()

        refute_receive {:signals, _subscriber, _received_signals}

        assert length(subscribers) == 3
      end

      @tag :partition
      test "should distribute signals to subscribers using optional partition by function", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        opts = [
          concurrency_limit: 3,
          partition_by: fn %RecordedSignal{stream_id: stream_id} -> stream_id end
        ]

        {:ok, subscriber1} = Subscriber.start_link(signal_store, signal_store_meta, self(), opts)
        {:ok, subscriber2} = Subscriber.start_link(signal_store, signal_store_meta, self(), opts)
        {:ok, subscriber3} = Subscriber.start_link(signal_store, signal_store_meta, self(), opts)

        assert_receive {:subscribed, ^subscriber1, _subscription1}
        assert_receive {:subscribed, ^subscriber2, _subscription2}
        assert_receive {:subscribed, ^subscriber3, _subscription3}

        :ok = signal_store.publish(signal_store_meta, "stream0", 0, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        :ok = signal_store.publish(signal_store_meta, "stream0", 2, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream1", 2, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream2", 2, build_signals(2))

        :ok = signal_store.publish(signal_store_meta, "stream0", 4, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream1", 4, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 4, build_signals(1))

        assert_receive {:signals, subscriber1,
                        [%RecordedSignal{signal_number: 1, stream_id: "stream0"}] = signals1}

        assert_receive {:signals, subscriber2,
                        [%RecordedSignal{signal_number: 3, stream_id: "stream1"}] = signals2}

        assert_receive {:signals, subscriber3,
                        [%RecordedSignal{signal_number: 5, stream_id: "stream2"}] = signals3}

        refute_receive {:signals, _subscriber, _received_signals}

        :ok = Subscriber.ack(subscriber1, signals1)
        :ok = Subscriber.ack(subscriber2, signals2)
        :ok = Subscriber.ack(subscriber3, signals3)

        assert_receive {:signals, ^subscriber1,
                        [%RecordedSignal{signal_number: 2, stream_id: "stream0"}] = signals4}

        assert_receive {:signals, ^subscriber2,
                        [%RecordedSignal{signal_number: 4, stream_id: "stream1"}] = signals5}

        assert_receive {:signals, ^subscriber3,
                        [%RecordedSignal{signal_number: 6, stream_id: "stream2"}] = signals6}

        refute_receive {:signals, _subscriber, _received_signals}

        :ok = Subscriber.ack(subscriber1, signals4)
        :ok = Subscriber.ack(subscriber2, signals5)
        :ok = Subscriber.ack(subscriber3, signals6)

        assert_receive {:signals, ^subscriber1,
                        [%RecordedSignal{signal_number: 7, stream_id: "stream0"}] = signals7}

        assert_receive {:signals, ^subscriber2,
                        [%RecordedSignal{signal_number: 9, stream_id: "stream1"}] = signals8}

        assert_receive {:signals, ^subscriber3,
                        [%RecordedSignal{signal_number: 11, stream_id: "stream2"}] = signals9}

        refute_receive {:signals, _subscriber, _received_signals}

        :ok = Subscriber.ack(subscriber1, signals7)
        :ok = Subscriber.ack(subscriber2, signals8)
        :ok = Subscriber.ack(subscriber3, signals9)

        assert_receive {:signals, ^subscriber1,
                        [%RecordedSignal{signal_number: 8, stream_id: "stream0"}] = signals10}

        assert_receive {:signals, ^subscriber2,
                        [%RecordedSignal{signal_number: 10, stream_id: "stream1"}] = signals11}

        assert_receive {:signals, ^subscriber3,
                        [%RecordedSignal{signal_number: 12, stream_id: "stream2"}] = signals12}

        refute_receive {:signals, _subscriber, _received_signals}

        :ok = Subscriber.ack(subscriber1, signals10)
        :ok = Subscriber.ack(subscriber2, signals11)
        :ok = Subscriber.ack(subscriber3, signals12)

        assert_receive {:signals, ^subscriber1,
                        [%RecordedSignal{signal_number: 13, stream_id: "stream0"}] = signals13}

        assert_receive {:signals, ^subscriber2,
                        [%RecordedSignal{signal_number: 14, stream_id: "stream1"}] = signals14}

        assert_receive {:signals, ^subscriber3,
                        [%RecordedSignal{signal_number: 15, stream_id: "stream2"}] = signals15}

        refute_receive {:signals, _subscriber, _received_signals}

        :ok = Subscriber.ack(subscriber1, signals13)
        :ok = Subscriber.ack(subscriber2, signals14)
        :ok = Subscriber.ack(subscriber3, signals15)

        refute_receive {:signals, _subscriber, _received_signals}
      end

      test "should exclude stopped subscriber from receiving signals", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscriber1} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 2)

        {:ok, subscriber2} =
          Subscriber.start_link(signal_store, signal_store_meta, self(), concurrency_limit: 2)

        assert_receive {:subscribed, ^subscriber1, _subscription1}
        assert_receive {:subscribed, ^subscriber2, _subscription2}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(2))

        for n <- 1..2 do
          assert_receive {:signals, subscriber, [%RecordedSignal{signal_number: ^n}] = signals}

          :ok = Subscriber.ack(subscriber, signals)
        end

        stop_subscriber(subscriber1)

        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        for n <- 3..4 do
          assert_receive {:signals, ^subscriber2, [%RecordedSignal{signal_number: ^n}] = signals}

          :ok = Subscriber.ack(subscriber2, signals)
        end

        stop_subscriber(subscriber2)

        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(2))

        refute_receive {:signals, _subscriber, _received_signals}
      end
    end

    describe "unsubscribe from all streams" do
      test "should not receive further signals appended to any stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))

        assert_receive_signals(signal_store, signal_store_meta, subscription, count: 1, from: 1)

        :ok = unsubscribe(signal_store, signal_store_meta, subscription)

        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))
        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(3))

        refute_receive {:signals, _received_signals}
      end

      test "should resume subscription when subscribing again", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription1} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription1}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))

        assert_receive_signals(signal_store, signal_store_meta, subscription1, count: 1, from: 1)

        :ok = unsubscribe(signal_store, signal_store_meta, subscription1)

        {:ok, subscription2} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        assert_receive {:subscribed, ^subscription2}
        assert_receive_signals(signal_store, signal_store_meta, subscription2, count: 2, from: 2)
      end
    end

    describe "delete subscription" do
      test "should be deleted", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription1} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription1}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))

        assert_receive_signals(signal_store, signal_store_meta, subscription1, count: 1, from: 1)

        :ok = unsubscribe(signal_store, signal_store_meta, subscription1)

        assert :ok = signal_store.unsubscribe(signal_store_meta, :all, "subscriber")
      end

      test "should create new subscription after deletion", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscription1} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        assert_receive {:subscribed, ^subscription1}

        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))

        assert_receive_signals(signal_store, signal_store_meta, subscription1, count: 1, from: 1)

        :ok = unsubscribe(signal_store, signal_store_meta, subscription1)

        :ok = signal_store.unsubscribe(signal_store_meta, :all, "subscriber")

        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(2))

        refute_receive {:signals, _received_signals}

        {:ok, subscription2} =
          signal_store.subscribe_persistent(
            signal_store_meta,
            :all,
            "subscriber",
            self(),
            :origin,
            []
          )

        # Should receive all signals as subscription has been recreated from `:origin`
        assert_receive {:subscribed, ^subscription2}
        assert_receive_signals(signal_store, signal_store_meta, subscription2, count: 1, from: 1)
        assert_receive_signals(signal_store, signal_store_meta, subscription2, count: 2, from: 2)
      end
    end

    describe "resume subscription" do
      test "should resume from checkpoint", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(1))

        {:ok, subscriber1} = Subscriber.start_link(signal_store, signal_store_meta, self())

        assert_receive {:subscribed, ^subscriber1, _subscription}
        assert_receive {:signals, ^subscriber1, received_signals}
        assert length(received_signals) == 1
        assert Enum.map(received_signals, & &1.stream_id) == ["stream1"]

        :ok = Subscriber.ack(subscriber1, received_signals)

        assert_receive {:signals, ^subscriber1, received_signals}
        assert length(received_signals) == 1
        assert Enum.map(received_signals, & &1.stream_id) == ["stream2"]

        :ok = Subscriber.ack(subscriber1, received_signals)

        stop_subscriber(subscriber1)

        {:ok, subscriber2} = Subscriber.start_link(signal_store, signal_store_meta, self())

        assert_receive {:subscribed, ^subscriber2, _subscription}
        refute_receive {:signals, _subscriber, _received_signals}

        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(1))

        assert_receive {:signals, ^subscriber2, received_signals}
        assert length(received_signals) == 1
        assert Enum.map(received_signals, & &1.stream_id) == ["stream3"]

        :ok = Subscriber.ack(subscriber2, received_signals)

        refute_receive {:signals, _subscriber, _received_signals}
      end

      test "should resume subscription from last successful ack", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        :ok = signal_store.publish(signal_store_meta, "stream1", 0, build_signals(1))
        :ok = signal_store.publish(signal_store_meta, "stream2", 0, build_signals(1))

        {:ok, subscriber1} = Subscriber.start_link(signal_store, signal_store_meta, self())

        assert_receive {:subscribed, ^subscriber1, _subscription}

        assert_receive {:signals, ^subscriber1,
                        [%RecordedSignal{signal_number: 1, stream_id: "stream1"}] =
                          received_signals}

        :ok = Subscriber.ack(subscriber1, received_signals)

        assert_receive {:signals, ^subscriber1,
                        [%RecordedSignal{signal_number: 2, stream_id: "stream2"}]}

        stop_subscriber(subscriber1)

        {:ok, subscriber2} = Subscriber.start_link(signal_store, signal_store_meta, self())

        assert_receive {:subscribed, ^subscriber2, _subscription}

        # Receive signal #2 again because it wasn't ack'd
        assert_receive {:signals, ^subscriber2,
                        [%RecordedSignal{signal_number: 2, stream_id: "stream2"}] =
                          received_signals}

        :ok = Subscriber.ack(subscriber2, received_signals)

        :ok = signal_store.publish(signal_store_meta, "stream3", 0, build_signals(1))

        assert_receive {:signals, ^subscriber2,
                        [%RecordedSignal{signal_number: 3, stream_id: "stream3"}] =
                          received_signals}

        :ok = Subscriber.ack(subscriber2, received_signals)

        refute_receive {:signals, _subscriber, _received_signals}
      end
    end

    describe "subscription process" do
      test "should not stop subscriber process when subscription down", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscriber} = Subscriber.start_link(signal_store, signal_store_meta, self())

        ref = Process.monitor(subscriber)

        assert_receive {:subscribed, ^subscriber, subscription}

        shutdown_test_process(subscription)

        refute Process.alive?(subscription)
        assert Process.alive?(subscriber)
        refute_receive {:DOWN, ^ref, :process, ^subscriber, _reason}
      end

      test "should stop subscription process when subscriber down", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        {:ok, subscriber} = Subscriber.start_link(signal_store, signal_store_meta, self())

        assert_receive {:subscribed, ^subscriber, subscription}

        ref = Process.monitor(subscription)

        stop_subscriber(subscriber)

        assert_receive {:DOWN, ^ref, :process, ^subscription, _reason}
      end
    end

    defp unsubscribe(signal_store, signal_store_meta, subscription) do
      :ok = signal_store.unsubscribe(signal_store_meta, subscription)

      wait_for_signal_store()
    end

    defp stop_subscriber(subscriber) do
      shutdown_test_process(subscriber)

      wait_for_signal_store()
    end

    # Wait for the signal store
    defp wait_for_signal_store do
      wait = signal_store_wait()
      :timer.sleep(wait)
    end

    defp assert_receive_signals(signal_store, signal_store_meta, subscription, opts) do
      opts = Keyword.put(opts, :subscription, subscription)

      assert_receive_signals(signal_store, signal_store_meta, opts)
    end

    defp assert_receive_signals(signal_store, signal_store_meta, opts) do
      expected_count = Keyword.fetch!(opts, :count)
      from_signal_number = Keyword.get(opts, :from, 1)

      assert_receive {:signals, received_signals}
      assert_received_signals(received_signals, from_signal_number)

      case Keyword.get(opts, :subscription) do
        subscription when is_pid(subscription) ->
          last_signal = List.last(received_signals)

          signal_store.ack(signal_store_meta, subscription, last_signal)

        nil ->
          :ok
      end

      case expected_count - length(received_signals) do
        0 ->
          received_signals

        remaining when remaining > 0 ->
          opts =
            opts
            |> Keyword.put(:from, from_signal_number + length(received_signals))
            |> Keyword.put(:count, remaining)

          received_signals ++ assert_receive_signals(signal_store, signal_store_meta, opts)

        remaining when remaining < 0 ->
          flunk("Received #{abs(remaining)} more signal(s) than expected")
      end
    end

    defp assert_received_signals(received_signals, from_signal_number) do
      received_signals
      |> Enum.with_index(from_signal_number)
      |> Enum.each(fn {received_signal, expected_signal_number} ->
        assert received_signal.signal_number == expected_signal_number
      end)
    end

    defp build_signal(account_number) do
      %Signal{
        id: Jido.Util.generate_id(),
        source: Jido.Util.generate_id(),
        type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
        jido_metadata: %{"user_id" => "test"}
      }
    end

    defp build_signals(count) do
      for account_number <- 1..count, do: build_signal(account_number)
    end
  end
end
