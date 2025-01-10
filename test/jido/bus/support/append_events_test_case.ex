defmodule Jido.Bus.AppendSignalsTestCase do
  import JidoTest.SharedTestCase

  define_tests do
    import Jido.Util, only: [pluck: 2]

    alias Jido.Signal

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    describe "signal store adapter" do
      test "should implement `Jido.Bus.Adapter` behaviour", %{
        signal_store: signal_store
      } do
        assert_implements(signal_store, Jido.Bus.Adapter)
      end
    end

    describe "append signals to a stream" do
      test "should append signals", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok == signal_store.publish(signal_store_meta, "stream", 0, build_signals(1))
        assert :ok == signal_store.publish(signal_store_meta, "stream", 1, build_signals(2))
        assert :ok == signal_store.publish(signal_store_meta, "stream", 3, build_signals(3))
      end

      test "should append signals with `:any_version` without checking expected version", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :any_version,
                   build_signals(3)
                 )

        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :any_version,
                   build_signals(2)
                 )

        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :any_version,
                   build_signals(1)
                 )
      end

      test "should append signals with `:no_stream` parameter", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :no_stream,
                   build_signals(2)
                 )
      end

      test "should fail when stream already exists with `:no_stream` parameter", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :no_stream,
                   build_signals(2)
                 )

        assert {:error, :stream_exists} ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :no_stream,
                   build_signals(1)
                 )
      end

      test "should append signals with `:stream_exists` parameter", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :no_stream,
                   build_signals(2)
                 )

        assert :ok ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :stream_exists,
                   build_signals(1)
                 )
      end

      test "should fail with `:stream_exists` parameter when stream does not exist", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert {:error, :stream_not_found} ==
                 signal_store.publish(
                   signal_store_meta,
                   "stream",
                   :stream_exists,
                   build_signals(1)
                 )
      end

      test "should fail to append to a stream because of wrong expected version when no stream",
           %{signal_store: signal_store, signal_store_meta: signal_store_meta} do
        assert {:error, :wrong_expected_version} ==
                 signal_store.publish(signal_store_meta, "stream", 1, build_signals(1))
      end

      test "should fail to append to a stream because of wrong expected version", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert :ok == signal_store.publish(signal_store_meta, "stream", 0, build_signals(3))

        assert {:error, :wrong_expected_version} ==
                 signal_store.publish(signal_store_meta, "stream", 0, build_signals(1))

        assert {:error, :wrong_expected_version} ==
                 signal_store.publish(signal_store_meta, "stream", 1, build_signals(1))

        assert {:error, :wrong_expected_version} ==
                 signal_store.publish(signal_store_meta, "stream", 2, build_signals(1))

        assert :ok == signal_store.publish(signal_store_meta, "stream", 3, build_signals(1))
      end
    end

    describe "stream signals from an unknown stream" do
      test "should return stream not found error", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        assert {:error, :stream_not_found} ==
                 signal_store.replay(signal_store_meta, "unknownstream")
      end
    end

    describe "stream signals from an existing stream" do
      test "should read signals", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        jido_correlation_id = UUID.uuid4()
        jido_causation_id = UUID.uuid4()
        signals = build_signals(4, jido_correlation_id, jido_causation_id)

        assert :ok == signal_store.publish(signal_store_meta, "stream", 0, signals)

        read_signals = signal_store.replay(signal_store_meta, "stream") |> Enum.to_list()
        assert length(read_signals) == 4
        assert coerce(signals) == coerce(read_signals)
        assert pluck(read_signals, :stream_version) == [1, 2, 3, 4]

        Enum.each(read_signals, fn signal ->
          assert_is_uuid(signal.signal_id)
          assert signal.stream_id == "stream"
          assert signal.jido_correlation_id == jido_correlation_id
          assert signal.jido_causation_id == jido_causation_id
          assert signal.metadata == %{"metadata" => "value"}
          assert %DateTime{} = signal.created_at
        end)

        read_signals = signal_store.replay(signal_store_meta, "stream", 3) |> Enum.to_list()
        assert coerce(Enum.slice(signals, 2, 2)) == coerce(read_signals)
        assert pluck(read_signals, :stream_version) == [3, 4]
      end

      test "should read from single stream", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        signals1 = build_signals(2)
        signals2 = build_signals(4)

        assert :ok == signal_store.publish(signal_store_meta, "stream", 0, signals1)
        assert :ok == signal_store.publish(signal_store_meta, "secondstream", 0, signals2)

        read_signals = signal_store.replay(signal_store_meta, "stream", 0) |> Enum.to_list()
        assert 2 == length(read_signals)
        assert coerce(signals1) == coerce(read_signals)

        read_signals =
          signal_store.replay(signal_store_meta, "secondstream", 0) |> Enum.to_list()

        assert 4 == length(read_signals)
        assert coerce(signals2) == coerce(read_signals)
      end

      test "should read signals in batches", %{
        signal_store: signal_store,
        signal_store_meta: signal_store_meta
      } do
        signals = build_signals(10)

        assert :ok == signal_store.publish(signal_store_meta, "stream", 0, signals)

        read_signals =
          signal_store.replay(signal_store_meta, "stream", 0, 2) |> Enum.to_list()

        assert length(read_signals) == 10
        assert coerce(signals) == coerce(read_signals)

        assert pluck(read_signals, :stream_version) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      end
    end

    defp build_signal(account_number, jido_correlation_id, jido_causation_id) do
      %Signal{
        id: UUID.uuid4(),
        source: "http://example.com/bank",
        jido_correlation_id: jido_correlation_id,
        jido_causation_id: jido_causation_id,
        type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
        metadata: %{"metadata" => "value"}
      }
    end

    defp build_signals(
           count,
           jido_correlation_id \\ UUID.uuid4(),
           jido_causation_id \\ UUID.uuid4()
         )

    defp build_signals(count, jido_correlation_id, jido_causation_id) do
      for account_number <- 1..count,
          do: build_signal(account_number, jido_correlation_id, jido_causation_id)
    end

    defp assert_is_uuid(uuid) do
      assert uuid |> UUID.string_to_binary!() |> is_binary()
    end

    # Returns `true` if module implements behaviour.
    defp assert_implements(module, behaviour) do
      all = Keyword.take(module.__info__(:attributes), [:behaviour])

      assert [behaviour] in Keyword.values(all)
    end

    defp coerce(signals) do
      Enum.map(
        signals,
        &%{
          jido_causation_id: &1.jido_causation_id,
          jido_correlation_id: &1.jido_correlation_id,
          data: &1.data,
          metadata: &1.metadata
        }
      )
    end
  end
end
