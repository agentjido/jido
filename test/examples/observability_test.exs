defmodule JidoExampleTest.ObservabilityTest do
  @moduledoc """
  Example test demonstrating Jido.Observe for agent observability.

  This test shows:
  - How to wrap work in telemetry spans with `with_span/3`
  - How async spans work with `start_span/2` and `finish_span/2`
  - How exception spans capture error metadata
  - How debug event gating works via config
  - How trace correlation enriches span metadata

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.AgentServer
  alias Jido.Observe
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  # ===========================================================================
  # TELEMETRY COLLECTOR: Captures telemetry events for assertions
  # ===========================================================================

  defmodule TelemetryCollector do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts[:events] || [], opts)
    end

    def get_events(pid) do
      GenServer.call(pid, :get_events)
    end

    def clear(pid) do
      GenServer.call(pid, :clear)
    end

    @impl true
    def init(event_prefixes) do
      handler_id = make_ref() |> inspect()

      :telemetry.attach_many(
        handler_id,
        event_prefixes,
        &__MODULE__.handle_event/4,
        self()
      )

      {:ok, %{handler_id: handler_id, events: []}}
    end

    @impl true
    def terminate(_reason, %{handler_id: handler_id}) do
      :telemetry.detach(handler_id)
    end

    @impl true
    def handle_info({:telemetry_event, event, measurements, metadata}, state) do
      {:noreply, %{state | events: [{event, measurements, metadata} | state.events]}}
    end

    @impl true
    def handle_call(:get_events, _from, state) do
      {:reply, Enum.reverse(state.events), state}
    end

    def handle_call(:clear, _from, state) do
      {:reply, :ok, %{state | events: []}}
    end

    def handle_event(event, measurements, metadata, collector_pid) do
      send(collector_pid, {:telemetry_event, event, measurements, metadata})
    end
  end

  # ===========================================================================
  # ACTIONS: Demonstrate observability patterns
  # ===========================================================================

  defmodule ObservedWorkAction do
    @moduledoc false
    use Jido.Action,
      name: "observed_work",
      schema: [
        work_units: [type: :integer, default: 10]
      ]

    def run(params, context) do
      agent_id = Map.get(context, :agent_id, "unknown")

      Observe.with_span(
        [:jido, :example, :observed_work],
        %{agent_id: agent_id, action: "observed_work"},
        fn ->
          result = params.work_units * 2
          %{last_result: result}
        end
      )
      |> then(&{:ok, &1})
    end
  end

  defmodule ObservedAsyncAction do
    @moduledoc false
    use Jido.Action,
      name: "observed_async",
      schema: [
        delay_ms: [type: :integer, default: 10]
      ]

    def run(params, context) do
      agent_id = Map.get(context, :agent_id, "unknown")

      span_ctx =
        Observe.start_span(
          [:jido, :example, :observed_async],
          %{agent_id: agent_id, action: "observed_async"}
        )

      task =
        Task.async(fn ->
          Process.sleep(params.delay_ms)
          result = params.delay_ms * 3
          Observe.finish_span(span_ctx, %{result_value: result})
          result
        end)

      result = Task.await(task)
      {:ok, %{async_result: result}}
    end
  end

  # ===========================================================================
  # AGENT: Routes signals to observed actions
  # ===========================================================================

  defmodule ObserveExampleAgent do
    @moduledoc false
    use Jido.Agent,
      name: "observe_example_agent",
      schema: [
        last_result: [type: :integer, default: nil],
        async_result: [type: :integer, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"observed_work", ObservedWorkAction},
        {"observed_async", ObservedAsyncAction}
      ]
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "sync spans with with_span/3" do
    test "emits start and stop events with duration", %{jido: jido} do
      events = [
        [:jido, :example, :observed_work, :start],
        [:jido, :example, :observed_work, :stop]
      ]

      {:ok, collector} = TelemetryCollector.start_link(events: events)
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, pid} = Jido.start_agent(jido, ObserveExampleAgent, id: unique_id("observe"))

      signal = Signal.new!("observed_work", %{work_units: 5}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.last_result == 10

      eventually(fn ->
        events = TelemetryCollector.get_events(collector)
        length(events) >= 2
      end)

      events = TelemetryCollector.get_events(collector)

      start_event =
        Enum.find(events, fn {e, _, _} -> e == [:jido, :example, :observed_work, :start] end)

      stop_event =
        Enum.find(events, fn {e, _, _} -> e == [:jido, :example, :observed_work, :stop] end)

      assert start_event != nil
      assert stop_event != nil

      {_, start_measurements, start_metadata} = start_event
      {_, stop_measurements, stop_metadata} = stop_event

      assert is_integer(start_measurements.system_time)
      assert start_metadata.action == "observed_work"

      assert is_integer(stop_measurements.duration)
      assert stop_measurements.duration > 0
      assert stop_metadata.action == "observed_work"
    end
  end

  describe "exception spans" do
    test "emits start and exception events with error metadata" do
      events = [
        [:jido, :example, :exception_test, :start],
        [:jido, :example, :exception_test, :exception]
      ]

      {:ok, collector} = TelemetryCollector.start_link(events: events)
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      assert_raise RuntimeError, "Intentional failure", fn ->
        Observe.with_span(
          [:jido, :example, :exception_test],
          %{test: "exception"},
          fn ->
            raise "Intentional failure"
          end
        )
      end

      eventually(fn ->
        events = TelemetryCollector.get_events(collector)
        length(events) >= 2
      end)

      events = TelemetryCollector.get_events(collector)

      exception_event =
        Enum.find(events, fn {e, _, _} -> e == [:jido, :example, :exception_test, :exception] end)

      assert exception_event != nil

      {_, measurements, metadata} = exception_event

      assert is_integer(measurements.duration)
      assert metadata.kind == :error
      assert %RuntimeError{message: "Intentional failure"} = metadata.error
      assert is_list(metadata.stacktrace)
    end
  end

  describe "async spans with start_span/finish_span" do
    test "emits start and stop events with extra measurements", %{jido: jido} do
      events = [
        [:jido, :example, :observed_async, :start],
        [:jido, :example, :observed_async, :stop]
      ]

      {:ok, collector} = TelemetryCollector.start_link(events: events)
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, pid} = Jido.start_agent(jido, ObserveExampleAgent, id: unique_id("observe"))

      signal = Signal.new!("observed_async", %{delay_ms: 5}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.async_result == 15

      eventually(fn ->
        events = TelemetryCollector.get_events(collector)
        length(events) >= 2
      end)

      events = TelemetryCollector.get_events(collector)

      stop_event =
        Enum.find(events, fn {e, _, _} -> e == [:jido, :example, :observed_async, :stop] end)

      assert stop_event != nil

      {_, measurements, _metadata} = stop_event

      assert is_integer(measurements.duration)
      assert measurements.result_value == 15
    end
  end

  describe "debug event gating" do
    setup do
      original_config = Application.get_env(:jido, :observability, [])
      on_exit(fn -> Application.put_env(:jido, :observability, original_config) end)
      :ok
    end

    test "debug events are suppressed when debug_events: :off" do
      events = [[:jido, :example, :debug, :test]]

      {:ok, collector} = TelemetryCollector.start_link(events: events)
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      Application.put_env(:jido, :observability, debug_events: :off)

      Observe.emit_debug_event([:jido, :example, :debug, :test], %{value: 1}, %{source: "test"})

      Process.sleep(50)
      events = TelemetryCollector.get_events(collector)
      assert events == []
    end

    test "debug events are emitted when debug_events: :all" do
      events = [[:jido, :example, :debug, :test]]

      {:ok, collector} = TelemetryCollector.start_link(events: events)
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      Application.put_env(:jido, :observability, debug_events: :all)

      Observe.emit_debug_event([:jido, :example, :debug, :test], %{value: 42}, %{source: "test"})

      eventually(fn ->
        events = TelemetryCollector.get_events(collector)
        events != []
      end)

      [{event, measurements, metadata}] = TelemetryCollector.get_events(collector)

      assert event == [:jido, :example, :debug, :test]
      assert measurements.value == 42
      assert metadata.source == "test"
    end
  end

  describe "trace correlation" do
    test "spans include trace context when set in process" do
      events = [
        [:jido, :example, :traced_work, :start],
        [:jido, :example, :traced_work, :stop]
      ]

      {:ok, collector} = TelemetryCollector.start_link(events: events)
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      signal = Signal.new!("test.traced", %{}, source: "/test")
      {_traced_signal, trace} = TraceContext.ensure_from_signal(signal)

      assert trace.trace_id != nil
      assert trace.span_id != nil

      Observe.with_span(
        [:jido, :example, :traced_work],
        %{action: "traced_work"},
        fn ->
          :ok
        end
      )

      TraceContext.clear()

      eventually(fn ->
        events = TelemetryCollector.get_events(collector)
        length(events) >= 2
      end)

      events = TelemetryCollector.get_events(collector)

      start_event =
        Enum.find(events, fn {e, _, _} -> e == [:jido, :example, :traced_work, :start] end)

      {_, _measurements, metadata} = start_event

      assert metadata[:jido_trace_id] == trace.trace_id
      assert metadata[:jido_span_id] == trace.span_id
    end
  end
end
