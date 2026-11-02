defmodule Jido.Signal.TelemetryTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Telemetry
  alias Jido.Signal.Trace

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {event, measurements, metadata})
  end

  test "execute/4 adds trace metadata from a Signal" do
    signal = Signal.new!(type: "test.created", source: "/test")
    trace = Trace.new(trace_flags: "01")
    assert {:ok, signal} = Trace.put(signal, trace)

    event = [:jido, :signal, :test, :traced]
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    assert :ok =
             :telemetry.attach(
               handler_id,
               event,
               &__MODULE__.handle_event/4,
               test_pid
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = Telemetry.execute(event, %{count: 1}, %{signal_type: signal.type}, signal)

    assert_received {^event, %{count: 1}, metadata}
    assert metadata.jido_trace_id == trace.trace_id
    assert metadata.jido_span_id == trace.span_id
    assert metadata.jido_trace_flags == "01"
    assert metadata.signal_type == signal.type
  end

  test "execute/4 does not add empty trace metadata" do
    signal = Signal.new!(type: "test.created", source: "/test")
    event = [:jido, :signal, :test, :untraced]
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    assert :ok =
             :telemetry.attach(
               handler_id,
               event,
               &__MODULE__.handle_event/4,
               test_pid
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert :ok = Telemetry.execute(event, %{}, %{signal_type: signal.type}, signal)

    assert_received {^event, %{}, %{signal_type: "test.created"}}
  end

  test "execute/3 drops nil metadata values" do
    event = [:jido, :signal, :test, :plain]
    handler_id = {__MODULE__, make_ref()}
    test_pid = self()

    assert :ok =
             :telemetry.attach(
               handler_id,
               event,
               &__MODULE__.handle_event/4,
               test_pid
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    expected = %{keep: "value", false: false, zero: 0, empty: "", list: [], map: %{}}
    assert :ok = Telemetry.execute(event, %{count: 1}, Map.put(expected, :drop, nil))
    assert_received {^event, %{count: 1}, ^expected}

    pairs = [
      keep: "value",
      keep: nil,
      drop: nil,
      false: false,
      zero: 0,
      empty: "",
      list: [],
      map: %{}
    ]

    assert :ok = Telemetry.execute(event, %{count: 1}, pairs)
    assert_received {^event, %{count: 1}, ^expected}
  end
end
