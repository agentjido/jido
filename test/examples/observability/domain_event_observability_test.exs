defmodule JidoExampleTest.DomainEventObservabilityTest do
  @moduledoc """
  Example test for custom namespace observability patterns.

  Demonstrates:
  - Custom domain events via `Jido.Observe.emit_event/3`
  - Contract validation via `Jido.Observe.EventContract`
  - Correlated request root + async child spans
  - Terminal lifecycle states (`completed/failed/cancelled/rejected`)
  """
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.Observe
  alias Jido.Observe.EventContract
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  setup do
    TraceContext.clear()
    :ok
  end

  test "validates and emits custom namespace domain event" do
    events = [[:jido, :ai, :request, :completed]]
    handler_id = attach_handler(self(), events)
    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, validated} =
             EventContract.validate_event(
               [:jido, :ai, :request, :completed],
               %{duration_ms: 42},
               %{request_id: "req-1", terminal_state: :completed, model: "gpt-4.1"},
               required_metadata: [:request_id, :terminal_state],
               required_measurements: [:duration_ms]
             )

    assert :ok =
             Observe.emit_event(validated.event, validated.measurements, validated.metadata)

    assert_receive {:telemetry_event, [:jido, :ai, :request, :completed], %{duration_ms: 42},
                    metadata}

    assert metadata.request_id == "req-1"
    assert metadata.terminal_state == :completed
    assert metadata.model == "gpt-4.1"
  end

  test "correlates request root and async child spans with terminal lifecycle events" do
    events = [
      [:jido, :ai, :request, :start],
      [:jido, :ai, :request, :stop],
      [:jido, :ai, :request, :tool, :start],
      [:jido, :ai, :request, :tool, :stop],
      [:jido, :ai, :request, :completed],
      [:jido, :ai, :request, :failed],
      [:jido, :ai, :request, :cancelled],
      [:jido, :ai, :request, :rejected]
    ]

    handler_id = attach_handler(self(), events)
    on_exit(fn -> :telemetry.detach(handler_id) end)

    signal = Signal.new!("jido.ai.request", %{}, source: "/example")
    {_traced_signal, trace} = TraceContext.ensure_from_signal(signal)
    trace_metadata = TraceContext.to_telemetry_metadata()
    request_id = "req-42"

    root_span = Observe.start_span([:jido, :ai, :request], %{request_id: request_id})

    task =
      Task.async(fn ->
        child_metadata =
          trace_metadata
          |> Map.merge(%{request_id: request_id, tool: "search"})

        child_span = Observe.start_span([:jido, :ai, :request, :tool], child_metadata)
        Process.sleep(5)
        Observe.finish_span(child_span, %{result_count: 3})
      end)

    assert :ok = Task.await(task)

    for terminal_state <- [:completed, :failed, :cancelled, :rejected] do
      assert {:ok, validated} =
               EventContract.validate_event(
                 [:jido, :ai, :request, terminal_state],
                 %{duration_ms: 25},
                 %{request_id: request_id, terminal_state: terminal_state},
                 required_metadata: [:request_id, :terminal_state],
                 required_measurements: [:duration_ms]
               )

      assert :ok =
               Observe.emit_event(
                 validated.event,
                 validated.measurements,
                 Map.merge(validated.metadata, trace_metadata)
               )
    end

    Observe.finish_span(root_span, %{directive_count: 1})
    TraceContext.clear()

    received = collect_events(8)
    assert length(received) == 8

    assert Enum.any?(received, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :request, :start] and metadata.request_id == request_id and
               metadata.jido_trace_id == trace.trace_id
           end)

    assert Enum.any?(received, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :request, :tool, :start] and metadata.request_id == request_id and
               metadata.jido_trace_id == trace.trace_id
           end)

    assert Enum.any?(received, fn {event, _measurements, metadata} ->
             event == [:jido, :ai, :request, :stop] and metadata.request_id == request_id and
               metadata.jido_trace_id == trace.trace_id
           end)

    for terminal_state <- [:completed, :failed, :cancelled, :rejected] do
      assert Enum.any?(received, fn {event, measurements, metadata} ->
               event == [:jido, :ai, :request, terminal_state] and measurements.duration_ms == 25 and
                 metadata.request_id == request_id and
                 metadata.terminal_state == terminal_state and
                 metadata.jido_trace_id == trace.trace_id
             end)
    end
  end

  defp attach_handler(test_pid, events) do
    handler_id = "domain-observability-handler-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    handler_id
  end

  defp collect_events(count) do
    Enum.map(1..count, fn _index ->
      receive do
        {:telemetry_event, event, measurements, metadata} ->
          {event, measurements, metadata}
      after
        1_500 ->
          flunk("Timed out collecting telemetry events")
      end
    end)
  end
end
