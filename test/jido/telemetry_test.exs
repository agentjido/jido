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

  test "metrics expose only Agent Server events" do
    metrics = Telemetry.metrics()
    names = Enum.map(metrics, & &1.name)

    assert names == [
             [:jido, :agent_server, :signal, :stop, :count],
             [:jido, :agent_server, :signal, :stop, :duration],
             [:jido, :agent_server, :directive, :stop, :count]
           ]

    for metric <- metrics do
      assert metric.tag_values.(%{signal_type: "test"}).jido_instance == :global
      assert metric.tag_values.(%{jido_instance: __MODULE__}).jido_instance == __MODULE__
    end
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
