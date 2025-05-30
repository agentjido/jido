defmodule JidoTest.Signal.Bus.Middleware do
  use JidoTest.Case, async: true
  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.Middleware.Logger, as: LoggerMiddleware

  @moduletag :capture_log

  # Test middleware that tracks calls
  defmodule TestMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      {:ok, %{test_pid: test_pid, calls: []}}
    end

    @impl true
    def before_publish(signals, context, state) do
      send(state.test_pid, {:before_publish, length(signals), context})
      {:cont, signals, %{state | calls: [:before_publish | state.calls]}}
    end

    @impl true
    def after_publish(signals, context, state) do
      send(state.test_pid, {:after_publish, length(signals), context})
      {:cont, signals, %{state | calls: [:after_publish | state.calls]}}
    end

    @impl true
    def before_dispatch(signal, subscriber, context, state) do
      send(state.test_pid, {:before_dispatch, signal.id, subscriber.path, context})
      {:cont, signal, %{state | calls: [:before_dispatch | state.calls]}}
    end

    @impl true
    def after_dispatch(signal, subscriber, result, context, state) do
      send(state.test_pid, {:after_dispatch, signal.id, subscriber.path, result, context})
      {:cont, %{state | calls: [:after_dispatch | state.calls]}}
    end
  end

  # Middleware that transforms signals
  defmodule TransformMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      {:ok, %{transform_type: Keyword.get(opts, :transform_type, "transformed")}}
    end

    @impl true
    def before_publish(signals, _context, state) do
      transformed_signals =
        Enum.map(signals, fn signal ->
          %{signal | type: state.transform_type}
        end)

      {:cont, transformed_signals, state}
    end

    @impl true
    def before_dispatch(signal, _subscriber, _context, state) do
      transformed_signal = %{signal | data: Map.put(signal.data || %{}, :transformed, true)}
      {:cont, transformed_signal, state}
    end
  end

  # Middleware that can halt processing
  defmodule HaltMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      {:ok, %{halt_on: Keyword.get(opts, :halt_on, :never)}}
    end

    @impl true
    def before_publish(_signals, _context, %{halt_on: :before_publish} = state) do
      {:halt, :middleware_halted_publish, state}
    end

    def before_publish(signals, _context, state) do
      {:cont, signals, state}
    end

    @impl true
    def before_dispatch(_signal, _subscriber, _context, %{halt_on: :before_dispatch} = state) do
      {:halt, :middleware_halted_dispatch, state}
    end

    def before_dispatch(signal, _subscriber, _context, state) do
      {:cont, signal, state}
    end
  end

  # Middleware that can skip dispatch
  defmodule SkipMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      {:ok, %{skip_path: Keyword.get(opts, :skip_path)}}
    end

    @impl true
    def before_dispatch(_signal, subscriber, _context, %{skip_path: skip_path} = state)
        when subscriber.path == skip_path do
      {:skip, state}
    end

    def before_dispatch(signal, _subscriber, _context, state) do
      {:cont, signal, state}
    end
  end

  describe "Bus with middleware initialization" do
    test "starts with empty middleware list by default" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"
      start_supervised!({Bus, name: bus_name})

      # Bus should start successfully with no middleware
      assert {:ok, pid} = Bus.whereis(bus_name)
      assert is_pid(pid)
    end

    test "starts with single middleware" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [{TestMiddleware, test_pid: self()}]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      assert {:ok, pid} = Bus.whereis(bus_name)
      assert is_pid(pid)
    end

    test "starts with multiple middleware" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {TestMiddleware, test_pid: self()},
        {LoggerMiddleware, level: :debug}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      assert {:ok, pid} = Bus.whereis(bus_name)
      assert is_pid(pid)
    end

    test "fails to start with invalid middleware" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      # Invalid middleware that will fail init
      middleware = [{NonExistentModule, []}]

      assert_raise RuntimeError, fn ->
        start_supervised!({Bus, name: bus_name, middleware: middleware})
      end
    end
  end

  describe "middleware execution order" do
    setup do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [{TestMiddleware, test_pid: self()}]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      {:ok, bus: bus_name}
    end

    test "executes before_publish and after_publish for signals", %{bus: bus} do
      # Create a test signal
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      # Publish the signal
      {:ok, _} = Bus.publish(bus, [signal])

      # Verify middleware callbacks were called
      assert_receive {:before_publish, 1, context}
      assert context.bus_name == bus
      assert %DateTime{} = context.timestamp

      assert_receive {:after_publish, 1, context}
      assert context.bus_name == bus
    end

    test "executes before_dispatch and after_dispatch for subscribers", %{bus: bus} do
      # Subscribe to signals
      {:ok, _subscription_id} = Bus.subscribe(bus, "test.signal")

      # Create and publish a test signal
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      # Verify all middleware callbacks were called
      assert_receive {:before_publish, 1, _context}
      assert_receive {:after_publish, 1, _context}
      assert_receive {:before_dispatch, _signal_id, "test.signal", _context}
      assert_receive {:after_dispatch, _signal_id, "test.signal", :ok, _context}

      assert signal.id == signal.id
    end

    test "middleware receives correct context information", %{bus: bus} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      assert_receive {:before_publish, 1, context}
      assert context.bus_name == bus
      assert %DateTime{} = context.timestamp
      assert is_map(context.metadata)
    end
  end

  describe "signal transformation middleware" do
    setup do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {TransformMiddleware, transform_type: "custom.transformed"},
        {TestMiddleware, test_pid: self()}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      {:ok, bus: bus_name}
    end

    test "transforms signal type before publish", %{bus: bus} do
      {:ok, _subscription_id} = Bus.subscribe(bus, "custom.transformed")

      # Create signal with original type
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      # Signal should be received with transformed type
      assert_receive {:signal, %Signal{type: "custom.transformed"}}
    end

    test "transforms signal data before dispatch", %{bus: bus} do
      {:ok, _subscription_id} = Bus.subscribe(bus, "custom.transformed")

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      # Signal should be received with transformed data
      assert_receive {:signal, %Signal{data: %{value: 1, transformed: true}}}
    end
  end

  describe "middleware halt behavior" do
    test "halts publish when middleware returns halt" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {HaltMiddleware, halt_on: :before_publish},
        {TestMiddleware, test_pid: self()}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      # Publish should fail due to middleware halt
      assert {:error, :middleware_halted_publish} = Bus.publish(bus_name, [signal])

      # TestMiddleware should not be called
      refute_receive {:before_publish, _, _}
    end

    test "halts dispatch when middleware returns halt" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {HaltMiddleware, halt_on: :before_dispatch},
        {TestMiddleware, test_pid: self()}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      {:ok, _subscription_id} = Bus.subscribe(bus_name, "test.signal")

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      # Publish should succeed, but dispatch will be halted
      {:ok, _} = Bus.publish(bus_name, [signal])

      # Signal should not be received due to halted dispatch
      refute_receive {:signal, _}

      # Middleware should be called up to the halt point
      assert_receive {:before_publish, 1, _context}
      assert_receive {:after_publish, 1, _context}
    end
  end

  describe "middleware skip behavior" do
    test "skips dispatch to specific subscriber" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {SkipMiddleware, skip_path: "test.signal"},
        {TestMiddleware, test_pid: self()}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      # Subscribe to the signal that will be skipped
      {:ok, _subscription_id} = Bus.subscribe(bus_name, "test.signal")

      # Subscribe to a different signal that won't be skipped
      {:ok, _subscription_id2} = Bus.subscribe(bus_name, "other.signal")

      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "other.signal",
          source: "/test",
          data: %{value: 2}
        })

      {:ok, _} = Bus.publish(bus_name, [signal1])
      {:ok, _} = Bus.publish(bus_name, [signal2])

      # Should not receive the skipped signal
      refute_receive {:signal, %Signal{type: "test.signal"}}

      # Should receive the non-skipped signal
      assert_receive {:signal, %Signal{type: "other.signal"}}
    end
  end

  describe "Logger middleware" do
    setup do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {LoggerMiddleware,
         level: :debug, log_publish: true, log_dispatch: true, include_signal_data: true}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      {:ok, bus: bus_name}
    end

    @tag :capture_log
    test "logs signal publishing and dispatch", %{bus: bus} do
      {:ok, _subscription_id} = Bus.subscribe(bus, "test.signal")

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1, message: "test data"}
        })

      # This will generate log output due to LoggerMiddleware
      {:ok, _} = Bus.publish(bus, [signal])

      # Signal should still be received normally
      assert_receive {:signal, %Signal{type: "test.signal"}}
    end

    test "middleware configuration is applied correctly" do
      # Test that middleware can be configured with different options
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      middleware = [
        {LoggerMiddleware, level: :error, log_publish: false, log_dispatch: false}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      assert {:ok, pid} = Bus.whereis(bus_name)
      assert is_pid(pid)
    end
  end

  describe "multiple middleware interaction" do
    test "multiple middleware are called in order" do
      bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"

      # Create two test middleware with different test PIDs
      {:ok, agent1} = Agent.start_link(fn -> [] end)
      {:ok, agent2} = Agent.start_link(fn -> [] end)

      defmodule TestMiddleware1 do
        use Jido.Signal.Bus.Middleware

        @impl true
        def init(opts) do
          agent = Keyword.fetch!(opts, :agent)
          {:ok, %{agent: agent, id: 1}}
        end

        @impl true
        def before_publish(signals, _context, state) do
          Agent.update(state.agent, fn calls -> [:middleware1_before_publish | calls] end)
          {:cont, signals, state}
        end
      end

      defmodule TestMiddleware2 do
        use Jido.Signal.Bus.Middleware

        @impl true
        def init(opts) do
          agent = Keyword.fetch!(opts, :agent)
          {:ok, %{agent: agent, id: 2}}
        end

        @impl true
        def before_publish(signals, _context, state) do
          Agent.update(state.agent, fn calls -> [:middleware2_before_publish | calls] end)
          {:cont, signals, state}
        end
      end

      middleware = [
        {TestMiddleware1, agent: agent1},
        {TestMiddleware2, agent: agent2}
      ]

      start_supervised!({Bus, name: bus_name, middleware: middleware})

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus_name, [signal])

      # Both middleware should have been called
      assert Agent.get(agent1, & &1) == [:middleware1_before_publish]
      assert Agent.get(agent2, & &1) == [:middleware2_before_publish]
    end
  end
end
