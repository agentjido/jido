defmodule JidoTest.Telemetry.ApiTest do
  use Covenant.Case, component: "jido.telemetry", async: false

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

  @tag obligation: ["jido.telemetry.I1", "jido.telemetry.I7"]
  test "the public API is metrics and OpenTelemetry status" do
    assert function_exported?(Telemetry, :metrics, 0)
    assert function_exported?(Telemetry, :open_telemetry?, 0)
    refute function_exported?(Telemetry, :setup, 0)
    refute Code.ensure_loaded?(Jido.Telemetry.Formatter)
  end

  @tag obligation: "jido.telemetry.I1"
  test "default metrics use semantic events and fixed vocabulary tags" do
    metrics = Telemetry.metrics()
    names = Enum.map(metrics, & &1.name)

    spans = [
      {[:jido, :agent_server, :turn], [:stop], [:status, :stage]},
      {[:jido, :persistence, :operation], [:stop, :exception],
       [:operation, :status, :persistence_reason]}
    ]

    points = [
      {[:jido, :agent_server, :lifecycle, :start], []},
      {[:jido, :agent_server, :lifecycle, :stop], []},
      {[:jido, :agent_server, :commit], [:status]},
      {[:jido, :agent_server, :directives, :returned], []},
      {[:jido, :agent_server, :effects, :start], []},
      {[:jido, :agent_server, :effects, :stop], [:status, :stage]},
      {[:jido, :agent_server, :turn, :settled], [:status, :stage]}
    ]

    assert length(names) == 13
    assert length(Enum.uniq(names)) == length(names)

    for {prefix, endings, tags} <- spans, ending <- endings, kind <- [:count, :duration] do
      metric = Enum.find(metrics, &(&1.name == prefix ++ [ending, kind]))
      assert metric.event_name == prefix ++ [ending]
      assert metric.tags == tags
      if kind == :duration, do: assert(metric.unit == :millisecond)
    end

    for {event, tags} <- points do
      assert %Elixir.Telemetry.Metrics.Counter{event_name: ^event, tags: ^tags} =
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

  @tag obligation: ["jido.telemetry.I1", "jido.telemetry.I4"]
  test "the default semantic handler attaches once and handles its catalog" do
    id = "jido-semantic-logger"
    :telemetry.detach(id)
    on_exit(&Telemetry.attach_default_handler/0)
    Application.put_env(:jido, :telemetry, semantic_log_mode: :all)

    assert :ok = Telemetry.attach_default_handler()
    attached = Enum.count(:telemetry.list_handlers([]), &(&1.id == id))
    assert attached > 0
    assert :ok = Telemetry.attach_default_handler()
    assert Enum.count(:telemetry.list_handlers([]), &(&1.id == id)) == attached

    log =
      capture_log(fn ->
        :telemetry.execute(
          [:jido, :agent_server, :commit],
          %{state_version_after: 1},
          %{status: :ok}
        )
      end)

    assert log =~ "[debug] [jido.semantic] event=agent_server.commit"
  end

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I4"]
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

    assert log =~ "[warning]"
    assert log =~ "status=conflict"
  end

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I4", "jido.telemetry.I8"]
  test "semantic log configuration and formatting fail closed at exact bounds" do
    event = [:jido, :persistence, :operation, :stop]
    exact_id = String.duplicate("b", 128)
    long_id = "X" <> String.duplicate("a", 128)
    kept_id = "X" <> String.duplicate("a", 124) <> "..."

    Application.put_env(:jido, :telemetry, %{
      semantic_log_mode: :interesting,
      semantic_slow_threshold_ms: 2
    })

    log =
      capture_log(fn ->
        assert :ok =
                 Telemetry.handle_semantic_event(
                   event,
                   %{duration: native_ms(2)},
                   %{agent_id: long_id, operation: :load, status: :ok},
                   nil
                 )
      end)

    assert log =~ "agent_id=#{kept_id} duration="
    assert log =~ " operation=load"
    refute log =~ long_id

    exact_log =
      capture_log(fn ->
        Telemetry.handle_semantic_event(
          event,
          %{duration: native_ms(2)},
          %{agent_id: exact_id, status: :ok},
          nil
        )
      end)

    assert exact_log =~ "agent_id=#{exact_id}"
    refute exact_log =~ "#{String.slice(exact_id, 0, 125)}..."

    for config <- [
          %{semantic_log_mode: :interesting, semantic_slow_threshold_ms: 3},
          [semantic_log_mode: :invalid, semantic_slow_threshold_ms: -1],
          :invalid
        ] do
      Application.put_env(:jido, :telemetry, config)

      assert capture_log(fn ->
               assert :ok =
                        Telemetry.handle_semantic_event(
                          event,
                          %{duration: native_ms(2)},
                          %{status: :ok},
                          nil
                        )
             end) == ""
    end

    Application.put_env(:jido, :telemetry, semantic_log_mode: :errors)

    assert capture_log(fn ->
             assert :ok = Telemetry.handle_semantic_event(event, %{}, %{}, nil)
           end) == ""

    Application.put_env(:jido, :telemetry, semantic_log_mode: :all)
    assert Telemetry.handle_semantic_event(:invalid, :invalid, :invalid, nil) == :ok
  end

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I4", "jido.telemetry.I8"]
  test "semantic log strings stay on one line and within the byte limit" do
    Application.put_env(:jido, :telemetry, semantic_log_mode: :all)
    event = [:jido, :agent_server, :turn, :stop]
    unsafe_id = "agent\nforged\rvalue\t\\tail\v"

    log =
      capture_log(fn ->
        Telemetry.handle_semantic_event(event, %{}, %{agent_id: unsafe_id, status: :ok}, nil)
      end)

    assert log =~ "agent_id=agent\\nforged\\rvalue\\t\\\\tail\\u{B}"
    refute log =~ "agent\nforged"

    unicode_id = String.duplicate("😀", 64)

    unicode_log =
      capture_log(fn ->
        Telemetry.handle_semantic_event(event, %{}, %{agent_id: unicode_id, status: :ok}, nil)
      end)

    assert [_, logged_id] = Regex.run(~r/agent_id=(\S+)/u, unicode_log)
    assert byte_size(logged_id) <= 128
    assert String.valid?(logged_id)
    assert String.ends_with?(logged_id, "...")

    boundaries = [
      {31, "\\u{1F}"},
      {32, " "},
      {33, "!"},
      {126, "~"},
      {127, "\\u{7F}"},
      {128, "\\u{80}"},
      {158, "\\u{9E}"},
      {159, "\\u{9F}"},
      {160, <<160::utf8>>},
      {0x2027, <<0x2027::utf8>>},
      {0x2028, "\\u2028"},
      {0x2029, "\\u2029"},
      {0x202A, <<0x202A::utf8>>}
    ]

    for {codepoint, rendered} <- boundaries do
      boundary_log =
        capture_log(fn ->
          Telemetry.handle_semantic_event(
            event,
            %{},
            %{agent_id: "x" <> <<codepoint::utf8>>, status: :ok},
            nil
          )
        end)

      assert boundary_log =~ "agent_id=x#{rendered} schema_version=1"
    end
  end

  @tag obligation: "jido.telemetry.I4"
  test "interesting logging uses exact duration and threshold boundaries" do
    event = [:jido, :persistence, :operation, :stop]
    metadata = %{operation: :load, status: :ok}

    Application.put_env(:jido, :telemetry,
      semantic_log_mode: :interesting,
      semantic_slow_threshold_ms: 2
    )

    assert capture_log(fn ->
             Telemetry.handle_semantic_event(event, %{duration: native_us(1_999)}, metadata, nil)
           end) == ""

    assert capture_log(fn ->
             Telemetry.handle_semantic_event(event, %{duration: native_us(2_001)}, metadata, nil)
           end) =~ "event=persistence.operation.stop"

    Application.put_env(:jido, :telemetry,
      semantic_log_mode: :interesting,
      semantic_slow_threshold_ms: 0
    )

    assert capture_log(fn ->
             Telemetry.handle_semantic_event(event, %{duration: 0}, metadata, nil)
           end) =~ "event=persistence.operation.stop"

    assert capture_log(fn -> Telemetry.handle_semantic_event(event, %{}, metadata, nil) end) == ""

    Application.put_env(:jido, :telemetry,
      semantic_log_mode: :interesting,
      semantic_slow_threshold_ms: -1
    )

    assert capture_log(fn ->
             Telemetry.handle_semantic_event(event, %{duration: 0}, metadata, nil)
           end) == ""

    Application.put_env(:jido, :telemetry, semantic_log_mode: :interesting)

    assert capture_log(fn ->
             Telemetry.handle_semantic_event(event, %{duration: native_ms(999)}, metadata, nil)
           end) == ""

    assert capture_log(fn ->
             Telemetry.handle_semantic_event(event, %{duration: native_ms(1_000)}, metadata, nil)
           end) =~ "event=persistence.operation.stop"
  end

  @tag obligation: "jido.telemetry.I4"
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

  @tag obligation: "jido.telemetry.I4"
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

  @tag obligation: "jido.telemetry.I4"
  test "non-instance values cannot select a debug override" do
    invalid_instance = "not-an-instance"
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Debug.enable(invalid_instance, :verbose)
    on_exit(fn -> Debug.reset(invalid_instance) end)

    log =
      capture_log(fn ->
        Semantic.point(
          [:jido, :agent_server, :turn, :stop],
          %{jido_instance: invalid_instance, status: :ok, stage: :commit}
        )
      end)

    assert log == ""
  end

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I3"]
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
  defp native_us(us), do: System.convert_time_unit(us, :microsecond, :native)
end
