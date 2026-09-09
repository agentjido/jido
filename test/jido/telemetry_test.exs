defmodule JidoTest.TelemetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Debug
  alias Jido.Telemetry

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
    handler_id = "jido-semantic-logger"
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

  test "default metrics use semantic events and fixed vocabulary tags" do
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

  test "per-instance debug mode takes priority over global semantic logging" do
    instance = :telemetry_debug_instance
    event = [:jido, :agent, :turn, :stop]
    metadata = %{jido_instance: instance, status: :ok, stage: :commit}
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Debug.enable(instance, :verbose)
    on_exit(fn -> Debug.reset(instance) end)

    log = capture_log(fn -> Telemetry.handle_semantic_event(event, %{}, metadata, nil) end)

    assert log =~ "event=agent.turn.stop"
  end

  test "semantic emission is independent of consumer configuration" do
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)

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

  defp native_ms(ms), do: System.convert_time_unit(ms, :millisecond, :native)
end
