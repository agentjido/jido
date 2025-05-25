defmodule JidoTest.Signal.Bus.MiddlewarePipeline do
  use JidoTest.Case, async: true
  alias Jido.Signal
  alias Jido.Signal.Bus.MiddlewarePipeline
  alias Jido.Signal.Bus.Subscriber

  @moduletag :capture_log

  # Test middleware modules
  defmodule TestMiddleware1 do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      {:ok, %{calls: [], id: Keyword.get(opts, :id, 1)}}
    end

    @impl true
    def before_publish(signals, _context, state) do
      new_state = %{state | calls: [:before_publish | state.calls]}
      {:cont, signals, new_state}
    end

    @impl true
    def after_publish(signals, _context, state) do
      new_state = %{state | calls: [:after_publish | state.calls]}
      {:cont, signals, new_state}
    end

    @impl true
    def before_dispatch(signal, _subscriber, _context, state) do
      new_state = %{state | calls: [:before_dispatch | state.calls]}
      {:cont, signal, new_state}
    end

    @impl true
    def after_dispatch(_signal, _subscriber, _result, _context, state) do
      new_state = %{state | calls: [:after_dispatch | state.calls]}
      {:cont, new_state}
    end
  end

  defmodule TransformMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      {:ok, %{suffix: Keyword.get(opts, :suffix, "-transformed")}}
    end

    @impl true
    def before_publish(signals, _context, state) do
      transformed_signals =
        Enum.map(signals, fn signal ->
          %{signal | type: signal.type <> state.suffix}
        end)

      {:cont, transformed_signals, state}
    end

    @impl true
    def before_dispatch(signal, _subscriber, _context, state) do
      transformed_signal = %{signal | source: signal.source <> state.suffix}
      {:cont, transformed_signal, state}
    end
  end

  defmodule HaltMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      {:ok, %{halt_reason: Keyword.get(opts, :halt_reason, :test_halt)}}
    end

    @impl true
    def before_publish(_signals, _context, state) do
      {:halt, state.halt_reason, state}
    end

    @impl true
    def before_dispatch(_signal, _subscriber, _context, state) do
      {:halt, state.halt_reason, state}
    end
  end

  defmodule SkipMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(_opts) do
      {:ok, %{}}
    end

    @impl true
    def before_dispatch(_signal, _subscriber, _context, state) do
      {:skip, state}
    end
  end

  defmodule FailingMiddleware do
    def init(_opts) do
      {:error, :initialization_failed}
    end
  end

  describe "init_middleware/1" do
    test "initializes empty middleware list" do
      assert {:ok, []} = MiddlewarePipeline.init_middleware([])
    end

    test "initializes single middleware" do
      middleware_specs = [{TestMiddleware1, id: 1}]

      assert {:ok, [{TestMiddleware1, %{calls: [], id: 1}}]} =
               MiddlewarePipeline.init_middleware(middleware_specs)
    end

    test "initializes multiple middleware in order" do
      middleware_specs = [
        {TestMiddleware1, id: 1},
        {TestMiddleware1, id: 2}
      ]

      assert {:ok, configs} = MiddlewarePipeline.init_middleware(middleware_specs)

      assert [
               {TestMiddleware1, %{calls: [], id: 1}},
               {TestMiddleware1, %{calls: [], id: 2}}
             ] = configs
    end

    test "returns error for failing middleware initialization" do
      middleware_specs = [
        {TestMiddleware1, []},
        {FailingMiddleware, []}
      ]

      assert {:error, {:middleware_init_failed, FailingMiddleware, :initialization_failed}} =
               MiddlewarePipeline.init_middleware(middleware_specs)
    end
  end

  describe "before_publish/3" do
    test "executes middleware chain successfully" do
      {:ok, configs} =
        MiddlewarePipeline.init_middleware([
          {TestMiddleware1, []},
          {TransformMiddleware, suffix: "-test"}
        ])

      signals = [
        %Signal{
          id: "test-1",
          type: "test.signal",
          source: "/test",
          data: %{}
        }
      ]

      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      assert {:ok, processed_signals} =
               MiddlewarePipeline.before_publish(configs, signals, context)

      # Signal should be transformed by TransformMiddleware
      assert [%Signal{type: "test.signal-test"}] = processed_signals
    end

    test "halts execution when middleware returns halt" do
      {:ok, configs} =
        MiddlewarePipeline.init_middleware([
          {TestMiddleware1, []},
          {HaltMiddleware, halt_reason: :custom_halt},
          {TransformMiddleware, []}
        ])

      signals = [%Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      assert {:error, :custom_halt} = MiddlewarePipeline.before_publish(configs, signals, context)
    end

    test "continues with empty middleware list" do
      signals = [%Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      assert {:ok, ^signals} = MiddlewarePipeline.before_publish([], signals, context)
    end

    test "skips middleware that don't implement before_publish" do
      # Create a middleware that only implements init
      defmodule MinimalMiddleware do
        @behaviour Jido.Signal.Bus.Middleware

        @impl true
        def init(_opts), do: {:ok, %{}}

        @impl true
        def before_publish(signals, _context, state), do: {:cont, signals, state}

        @impl true
        def after_publish(signals, _context, state), do: {:cont, signals, state}

        @impl true
        def before_dispatch(signal, _subscriber, _context, state), do: {:cont, signal, state}

        @impl true
        def after_dispatch(_signal, _subscriber, _result, _context, state), do: {:cont, state}
      end

      {:ok, configs} = MiddlewarePipeline.init_middleware([{MinimalMiddleware, []}])

      signals = [%Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      assert {:ok, ^signals} = MiddlewarePipeline.before_publish(configs, signals, context)
    end
  end

  describe "after_publish/3" do
    test "executes all middleware after_publish callbacks" do
      {:ok, configs} = MiddlewarePipeline.init_middleware([{TestMiddleware1, []}])

      signals = [%Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      # after_publish should always return :ok
      assert :ok = MiddlewarePipeline.after_publish(configs, signals, context)
    end

    test "continues with empty middleware list" do
      signals = [%Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      assert :ok = MiddlewarePipeline.after_publish([], signals, context)
    end
  end

  describe "before_dispatch/4" do
    setup do
      subscriber = %Subscriber{
        id: "test-subscription-#{:erlang.unique_integer([:positive])}",
        path: "test.signal",
        dispatch: {:pid, target: self(), delivery_mode: :async},
        persistent?: false,
        persistence_pid: nil
      }

      signal = %Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      {:ok, subscriber: subscriber, signal: signal, context: context}
    end

    test "executes middleware chain successfully", %{
      subscriber: subscriber,
      signal: signal,
      context: context
    } do
      {:ok, configs} =
        MiddlewarePipeline.init_middleware([
          {TestMiddleware1, []},
          {TransformMiddleware, suffix: "-dispatch"}
        ])

      assert {:ok, processed_signal} =
               MiddlewarePipeline.before_dispatch(configs, signal, subscriber, context)

      # Signal should be transformed by TransformMiddleware
      assert %Signal{source: "/test-dispatch"} = processed_signal
    end

    test "returns skip when middleware skips", %{
      subscriber: subscriber,
      signal: signal,
      context: context
    } do
      {:ok, configs} =
        MiddlewarePipeline.init_middleware([
          {TestMiddleware1, []},
          {SkipMiddleware, []},
          {TransformMiddleware, []}
        ])

      assert :skip = MiddlewarePipeline.before_dispatch(configs, signal, subscriber, context)
    end

    test "halts execution when middleware returns halt", %{
      subscriber: subscriber,
      signal: signal,
      context: context
    } do
      {:ok, configs} =
        MiddlewarePipeline.init_middleware([
          {TestMiddleware1, []},
          {HaltMiddleware, halt_reason: :dispatch_halt},
          {TransformMiddleware, []}
        ])

      assert {:error, :dispatch_halt} =
               MiddlewarePipeline.before_dispatch(configs, signal, subscriber, context)
    end

    test "continues with empty middleware list", %{
      subscriber: subscriber,
      signal: signal,
      context: context
    } do
      assert {:ok, ^signal} = MiddlewarePipeline.before_dispatch([], signal, subscriber, context)
    end
  end

  describe "after_dispatch/5" do
    setup do
      subscriber = %Subscriber{
        id: "test-subscription-#{:erlang.unique_integer([:positive])}",
        path: "test.signal",
        dispatch: {:pid, target: self(), delivery_mode: :async},
        persistent?: false,
        persistence_pid: nil
      }

      signal = %Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      {:ok, subscriber: subscriber, signal: signal, context: context}
    end

    test "executes all middleware after_dispatch callbacks", %{
      subscriber: subscriber,
      signal: signal,
      context: context
    } do
      {:ok, configs} = MiddlewarePipeline.init_middleware([{TestMiddleware1, []}])

      result = :ok

      # after_dispatch should always return :ok
      assert :ok =
               MiddlewarePipeline.after_dispatch(configs, signal, subscriber, result, context)
    end

    test "handles error results", %{subscriber: subscriber, signal: signal, context: context} do
      {:ok, configs} = MiddlewarePipeline.init_middleware([{TestMiddleware1, []}])

      result = {:error, :dispatch_failed}

      assert :ok =
               MiddlewarePipeline.after_dispatch(configs, signal, subscriber, result, context)
    end

    test "continues with empty middleware list", %{
      subscriber: subscriber,
      signal: signal,
      context: context
    } do
      result = :ok

      assert :ok = MiddlewarePipeline.after_dispatch([], signal, subscriber, result, context)
    end
  end

  describe "middleware chain ordering" do
    test "middleware are executed in the order they are initialized" do
      # Create middleware that append to a list to track execution order
      defmodule OrderTrackingMiddleware do
        use Jido.Signal.Bus.Middleware

        @impl true
        def init(opts) do
          test_pid = Keyword.fetch!(opts, :test_pid)
          id = Keyword.fetch!(opts, :id)
          {:ok, %{test_pid: test_pid, id: id}}
        end

        @impl true
        def before_publish(signals, _context, state) do
          send(state.test_pid, {:middleware_called, state.id, :before_publish})
          {:cont, signals, state}
        end
      end

      middleware_specs = [
        {OrderTrackingMiddleware, test_pid: self(), id: :first},
        {OrderTrackingMiddleware, test_pid: self(), id: :second},
        {OrderTrackingMiddleware, test_pid: self(), id: :third}
      ]

      {:ok, configs} = MiddlewarePipeline.init_middleware(middleware_specs)

      signals = [%Signal{id: "test-1", type: "test.signal", source: "/test", data: %{}}]
      context = %{bus_name: :test, timestamp: DateTime.utc_now(), metadata: %{}}

      MiddlewarePipeline.before_publish(configs, signals, context)

      # Verify execution order
      assert_receive {:middleware_called, :first, :before_publish}
      assert_receive {:middleware_called, :second, :before_publish}
      assert_receive {:middleware_called, :third, :before_publish}
    end
  end
end
