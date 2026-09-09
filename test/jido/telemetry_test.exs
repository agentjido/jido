defmodule JidoTest.TelemetryTest do
  use ExUnit.Case, async: false

  alias Jido.Telemetry
  import ExUnit.CaptureLog

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

  test "setup/0 is idempotent" do
    assert :ok = Telemetry.setup()
    assert :ok = Telemetry.setup()
  end

  test "setup/0 does not detach an existing handler" do
    handler_id = "jido-agent-metrics"
    event = [:jido, :telemetry, :sentinel]
    test_pid = self()

    :telemetry.detach(handler_id)

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn event, _measurements, _metadata, pid -> send(pid, {:sentinel, event}) end,
        test_pid
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Telemetry.setup()
    end)

    assert :ok = Telemetry.setup()
    :telemetry.execute(event, %{}, %{})
    assert_receive {:sentinel, ^event}
  end

  test "default metrics use semantic events and only fixed vocabulary tags" do
    metrics = Telemetry.metrics()
    names = Enum.map(metrics, & &1.name)

    assert names == [
             [:jido, :agent, :lifecycle, :stop, :count],
             [:jido, :agent, :lifecycle, :stop, :duration],
             [:jido, :agent, :turn, :stop, :count],
             [:jido, :agent, :turn, :stop, :duration],
             [:jido, :agent, :turn, :settled, :count],
             [:jido, :agent, :turn, :settled, :duration],
             [:jido, :agent, :commit, :stop, :count],
             [:jido, :agent, :commit, :stop, :duration],
             [:jido, :agent, :directive, :stop, :count],
             [:jido, :agent, :directive, :stop, :duration],
             [:jido, :agent, :admission, :rejected, :count],
             [:jido, :persistence, :operation, :stop, :count],
             [:jido, :persistence, :operation, :stop, :duration],
             [:jido, :topology, :operation, :stop, :count],
             [:jido, :topology, :operation, :stop, :duration]
           ]

    allowed =
      ~w(operation status stage admission_reason persistence_reason topology_operation component_kind)a

    for metric <- metrics, tag <- metric.tags do
      assert tag in allowed
      refute tag in ~w(agent_id agent_namespace signal_type error_code topology_id)a
    end

    legacy = Telemetry.legacy_metrics()

    for metric <- legacy do
      assert metric.tag_values.(%{signal_type: "test"}).jido_instance == :global
      assert metric.tag_values.(%{jido_instance: __MODULE__}).jido_instance == __MODULE__
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

  test "semantic emission is independent of consumer and old redaction settings" do
    Application.put_env(:jido, :telemetry,
      semantic_log_mode: :off,
      log_args: :full,
      redact_sensitive: false
    )

    event = [:jido, :agent, :admission, :rejected]
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
             Jido.Telemetry.Semantic.point(
               event,
               %{status: :rejected, admission_reason: :overloaded, private: "secret"},
               %{queue_depth: 2}
             )

    assert_receive {:semantic_event, ^event, %{queue_depth: 2}, metadata}
    assert metadata.schema_version == 1
    assert metadata.status == :rejected
    refute Map.has_key?(metadata, :private)
  end

  test "trace logs every completed Signal and Directive with bounded summaries" do
    Application.put_env(:jido, :telemetry, log_level: :trace)

    log =
      capture_log(fn ->
        emit_stop(:signal, %{signal_type: "test", directive_count: 2, directive_types: %{emit: 2}})

        emit_stop(:signal, %{signal_type: "empty"})
        emit_stop(:directive, %{directive_type: "Emit"}, %{result: :ok})
      end)

    assert log =~ "[signal] type=test directives=2 Emit=2"
    assert log =~ "[signal] type=empty directives=0"
    assert log =~ "[directive] type=Emit result=ok"
  end

  test "debug selects slow, effectful, interesting, and failed Signals" do
    Application.put_env(:jido, :telemetry,
      log_level: :debug,
      slow_signal_threshold_ms: 10,
      interesting_signal_types: ["interesting"]
    )

    log =
      capture_log(fn ->
        emit_stop(:signal, %{signal_type: "quiet"})
        emit_stop(:signal, %{signal_type: "slow"}, %{duration: native_ms(11)})
        emit_stop(:signal, %{signal_type: "effects"}, %{directive_count: 1})
        emit_stop(:signal, %{signal_type: "interesting"})
        emit_stop(:signal, %{signal_type: "failed", error: :invalid})
      end)

    refute log =~ "type=quiet"
    for type <- ["slow", "effects", "interesting", "failed"], do: assert(log =~ "type=#{type}")
  end

  test "debug selects slow, interesting, and failed Directives" do
    Application.put_env(:jido, :telemetry, log_level: :debug, slow_directive_threshold_ms: 10)

    log =
      capture_log(fn ->
        emit_stop(:directive, %{directive_type: "Quiet"})
        emit_stop(:directive, %{directive_type: "Slow"}, %{duration: native_ms(11)})
        emit_stop(:directive, %{directive_type: "Tool"})
        emit_stop(:directive, %{directive_type: "Failed", error: :invalid})
      end)

    refute log =~ "type=Quiet"
    for type <- ["Slow", "Tool", "Failed"], do: assert(log =~ "type=#{type}")
  end

  test "exception logs remain visible at the normal telemetry level" do
    Application.put_env(:jido, :telemetry, log_level: :info)

    log =
      capture_log(fn ->
        for kind <- [:signal, :directive] do
          Telemetry.handle_event(
            [:jido, :agent_server, kind, :exception],
            %{duration: 0},
            %{
              signal_type: "test",
              directive_type: "Tool",
              error: :failed
            },
            nil
          )
        end
      end)

    assert log =~ "[signal.error] type=test error=:failed"
    assert log =~ "[directive.error] type=Tool error=:failed"
  end

  defp emit_stop(kind, metadata, measurements \\ %{}) do
    Telemetry.handle_event([:jido, :agent_server, kind, :stop], measurements, metadata, nil)
  end

  defp native_ms(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  test "start events need no logging work" do
    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :signal, :start],
               %{},
               %{agent_id: "agent-1"},
               nil
             )

    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :directive, :start],
               %{},
               %{agent_id: "agent-1"},
               nil
             )
  end

  test "stop events accept bounded Agent metadata" do
    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :signal, :stop],
               %{duration: 1, directive_count: 0},
               %{
                 agent_id: "agent-1",
                 agent_module: __MODULE__,
                 signal_type: "test.signal",
                 jido_instance: nil
               },
               nil
             )

    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :directive, :stop],
               %{duration: 1, result: :ok},
               %{
                 agent_id: "agent-1",
                 directive_type: "Emit",
                 jido_instance: nil
               },
               nil
             )
  end
end
