defmodule JidoTest.TelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Debug
  alias Jido.Telemetry
  alias Jido.Telemetry.Semantic

  setup do
    config = Application.fetch_env(:jido, :telemetry)
    level = Logger.level()
    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: level)

      case config do
        {:ok, value} -> Application.put_env(:jido, :telemetry, value)
        :error -> Application.delete_env(:jido, :telemetry)
      end
    end)

    :ok
  end

  test "the public API is metrics and OpenTelemetry status" do
    assert function_exported?(Telemetry, :metrics, 0)
    assert function_exported?(Telemetry, :open_telemetry?, 0)
    refute function_exported?(Telemetry, :setup, 0)
    refute Code.ensure_loaded?(Jido.Telemetry.Formatter)
  end

  test "default metrics use semantic events and fixed vocabulary tags" do
    metrics = Telemetry.metrics()
    names = Enum.map(metrics, & &1.name)

    spans = [
      {[:jido, :agent_server, :turn], [:stop]},
      {[:jido, :persistence, :operation], [:stop, :exception]}
    ]

    points = [
      [:jido, :agent_server, :lifecycle, :start],
      [:jido, :agent_server, :lifecycle, :stop],
      [:jido, :agent_server, :commit],
      [:jido, :agent_server, :directives, :returned],
      [:jido, :agent_server, :effects, :start],
      [:jido, :agent_server, :effects, :stop],
      [:jido, :agent_server, :turn, :settled]
    ]

    assert length(names) == 13
    assert length(Enum.uniq(names)) == length(names)

    for {prefix, endings} <- spans, ending <- endings, kind <- [:count, :duration] do
      metric = Enum.find(metrics, &(&1.name == prefix ++ [ending, kind]))
      assert metric.event_name == prefix ++ [ending]
      if kind == :duration, do: assert(metric.unit == :millisecond)
    end

    for event <- points do
      assert %Elixir.Telemetry.Metrics.Counter{event_name: ^event} =
               Enum.find(metrics, &(&1.name == event ++ [:count]))

      refute Enum.any?(metrics, &(&1.name == event ++ [:duration]))
    end

    refute Enum.any?(
             metrics,
             &Enum.any?(&1.event_name, fn part -> part in [:agent, :topology] end)
           )

    allowed = ~w(operation status stage persistence_reason)a

    for metric <- metrics, tag <- metric.tags do
      assert tag in allowed
      refute tag in ~w(agent_id agent_namespace signal_type error_code topology_id)a
    end
  end

  test "semantic logger supports all four modes and removes private values" do
    event = [:jido, :persistence, :operation, :stop]
    measurements = %{duration: native_ms(2), revision_after: 2, private_count: 99}
    metadata = %{operation: :load, status: :ok, agent_id: "agent-1", private: "secret"}

    for {mode, expected?} <- [off: false, errors: false, interesting: true, all: true] do
      Application.put_env(:jido, :telemetry,
        semantic_log_mode: mode,
        semantic_slow_threshold_ms: 1
      )

      log =
        capture_log(fn -> Telemetry.handle_semantic_event(event, measurements, metadata, nil) end)

      assert log =~ "event=persistence.operation.stop" == expected?
      refute log =~ "secret"
      refute log =~ "private_count"
    end

    Application.put_env(:jido, :telemetry, semantic_log_mode: :errors)

    log =
      capture_log(fn ->
        Telemetry.handle_semantic_event(event, measurements, %{metadata | status: :conflict}, nil)
      end)

    assert log =~ "status=conflict"
  end

  test "effects failure is a semantic error log" do
    Application.put_env(:jido, :telemetry, semantic_log_mode: :errors)

    log =
      capture_log(fn ->
        Semantic.point(
          [:jido, :agent_server, :effects, :stop],
          %{agent_id: "agent-1", stage: :directive, status: :error},
          %{directive_count: 3, directive_completed: 1}
        )
      end)

    assert log =~ "event=agent_server.effects.stop"
    assert log =~ "status=error"
  end

  test "per-instance debug mode takes priority over global semantic logging" do
    instance = :telemetry_debug_instance
    event = [:jido, :agent_server, :turn, :stop]
    metadata = %{jido_instance: instance, status: :ok, stage: :commit}
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Debug.enable(instance, :verbose)
    on_exit(fn -> Debug.reset(instance) end)

    log = capture_log(fn -> Semantic.point(event, metadata) end)

    assert log =~ "event=agent_server.turn.stop"
  end

  test "semantic emission is independent of consumer configuration" do
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)

    event = [:jido, :agent_server, :effects, :stop]
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        event,
        fn event, measurements, metadata, owner ->
          send(owner, {:semantic_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :ok =
             Semantic.point(
               event,
               %{status: :error, stage: :directive, private: "secret"},
               %{directive_count: 2}
             )

    assert_receive {:semantic_event, ^event, %{directive_count: 2}, metadata}
    assert metadata.schema_version == 1
    assert metadata.status == :error
    refute Map.has_key?(metadata, :private)
  end

  defp native_ms(ms), do: System.convert_time_unit(ms, :millisecond, :native)
end
