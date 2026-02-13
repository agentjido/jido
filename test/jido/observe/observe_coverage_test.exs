defmodule JidoTest.ObserveCoverageTest do
  @moduledoc """
  Additional coverage tests for Jido.Observe.

  Targets uncovered paths:
  - Tracer error logging paths (span_start, span_stop, span_exception failures)
  - debug_enabled?/0 with various config values
  - emit_event/3 and emit_debug_event/3 behavior
  - redact/2 with various config scenarios
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Observe
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext
  alias JidoTest.Support.TestTracer

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :debug)

    original_config = Application.get_env(:jido, :observability)

    on_exit(fn ->
      Logger.configure(level: previous_level)

      if original_config do
        Application.put_env(:jido, :observability, original_config)
      else
        Application.delete_env(:jido, :observability)
      end
    end)

    :ok
  end

  describe "tracer error handling" do
    defmodule FailingTracer do
      @behaviour Jido.Observe.Tracer

      def span_start(_event_prefix, _metadata) do
        raise "span_start failure"
      end

      def span_stop(_tracer_ctx, _measurements) do
        raise "span_stop failure"
      end

      def span_exception(_tracer_ctx, _kind, _reason, _stacktrace) do
        raise "span_exception failure"
      end
    end

    test "logs warning when span_start fails" do
      Application.put_env(:jido, :observability, tracer: FailingTracer)

      log =
        capture_log(fn ->
          _span_ctx = Observe.start_span([:jido, :test, :failing], %{})
        end)

      assert log =~ "Jido.Observe tracer span_start/2 failed"
      assert log =~ "span_start failure"
    end

    test "logs warning when span_stop fails" do
      Application.put_env(:jido, :observability, tracer: FailingTracer)

      log =
        capture_log(fn ->
          span_ctx = Observe.start_span([:jido, :test, :failing], %{})
          Observe.finish_span(span_ctx)
        end)

      assert log =~ "Jido.Observe tracer span_stop/2 failed"
      assert log =~ "span_stop failure"
    end

    test "logs warning when span_exception fails" do
      Application.put_env(:jido, :observability, tracer: FailingTracer)

      log =
        capture_log(fn ->
          span_ctx = Observe.start_span([:jido, :test, :failing], %{})
          Observe.finish_span_error(span_ctx, :error, :some_error, [])
        end)

      assert log =~ "Jido.Observe tracer span_exception/4 failed"
      assert log =~ "span_exception failure"
    end

    test "with_span re-raises after tracer failure on exception" do
      Application.put_env(:jido, :observability, tracer: FailingTracer)

      log =
        capture_log(fn ->
          assert_raise RuntimeError, "original error", fn ->
            Observe.with_span([:jido, :test, :failing], %{}, fn ->
              raise "original error"
            end)
          end
        end)

      assert log =~ "span_exception failure"
    end
  end

  describe "debug_enabled?/0" do
    test "returns false when debug_events is :off" do
      Application.put_env(:jido, :observability, debug_events: :off)
      refute Observe.debug_enabled?()
    end

    test "returns false when debug_events is nil (not configured)" do
      Application.put_env(:jido, :observability, [])
      refute Observe.debug_enabled?()
    end

    test "returns false when observability config is not set" do
      Application.delete_env(:jido, :observability)
      refute Observe.debug_enabled?()
    end

    test "returns true when debug_events is :all" do
      Application.put_env(:jido, :observability, debug_events: :all)
      assert Observe.debug_enabled?()
    end

    test "returns true when debug_events is :minimal" do
      Application.put_env(:jido, :observability, debug_events: :minimal)
      assert Observe.debug_enabled?()
    end
  end

  describe "emit_debug_event/3" do
    setup do
      TraceContext.clear()
      test_pid = self()
      handler_id = "debug-event-handler-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :test, :debug],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:debug_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        TraceContext.clear()
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "enriches debug metadata with trace correlation when present" do
      Application.put_env(:jido, :observability, debug_events: :all)

      signal = Signal.new!("test.debug.trace", %{}, source: "/test")
      {_traced_signal, trace} = TraceContext.ensure_from_signal(signal)

      Observe.emit_debug_event([:jido, :test, :debug], %{count: 5}, %{key: "trace"})

      assert_receive {:debug_event, [:jido, :test, :debug], %{count: 5}, metadata}
      assert metadata.key == "trace"
      assert metadata.jido_trace_id == trace.trace_id
      assert metadata.jido_span_id == trace.span_id
    end

    test "emits event when debug_events is :all" do
      Application.put_env(:jido, :observability, debug_events: :all)

      Observe.emit_debug_event([:jido, :test, :debug], %{count: 1}, %{key: "value"})

      assert_receive {:debug_event, [:jido, :test, :debug], %{count: 1}, %{key: "value"}}
    end

    test "emits event when debug_events is :minimal" do
      Application.put_env(:jido, :observability, debug_events: :minimal)

      Observe.emit_debug_event([:jido, :test, :debug], %{count: 2}, %{key: "minimal"})

      assert_receive {:debug_event, [:jido, :test, :debug], %{count: 2}, %{key: "minimal"}}
    end

    test "does not emit event when debug_events is :off" do
      Application.put_env(:jido, :observability, debug_events: :off)

      Observe.emit_debug_event([:jido, :test, :debug], %{count: 3}, %{key: "off"})

      refute_receive {:debug_event, _, _, _}, 10
    end

    test "does not emit event when debug_events is not configured" do
      Application.put_env(:jido, :observability, [])

      Observe.emit_debug_event([:jido, :test, :debug], %{count: 4}, %{key: "none"})

      refute_receive {:debug_event, _, _, _}, 10
    end

    test "returns :ok regardless of debug state" do
      Application.put_env(:jido, :observability, debug_events: :off)
      assert Observe.emit_debug_event([:jido, :test, :debug]) == :ok

      Application.put_env(:jido, :observability, debug_events: :all)
      assert Observe.emit_debug_event([:jido, :test, :debug]) == :ok
    end

    test "works with default empty measurements and metadata" do
      Application.put_env(:jido, :observability, debug_events: :all)

      Observe.emit_debug_event([:jido, :test, :debug])

      assert_receive {:debug_event, [:jido, :test, :debug], %{}, %{}}
    end
  end

  describe "emit_event/3" do
    setup do
      TraceContext.clear()
      test_pid = self()
      handler_id = "event-handler-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :test, :event],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        TraceContext.clear()
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits event regardless of debug_events config" do
      Application.put_env(:jido, :observability, debug_events: :off)

      Observe.emit_event([:jido, :test, :event], %{count: 1}, %{key: "value"})

      assert_receive {:event, [:jido, :test, :event], %{count: 1}, %{key: "value"}}
    end

    test "returns :ok and supports default measurements and metadata" do
      assert Observe.emit_event([:jido, :test, :event]) == :ok
      assert_receive {:event, [:jido, :test, :event], %{}, %{}}
    end

    test "enriches metadata with current trace context" do
      signal = Signal.new!("test.event.trace", %{}, source: "/test")
      {_traced_signal, trace} = TraceContext.ensure_from_signal(signal)

      Observe.emit_event([:jido, :test, :event], %{count: 2}, %{key: "trace"})

      assert_receive {:event, [:jido, :test, :event], %{count: 2}, metadata}
      assert metadata.key == "trace"
      assert metadata.jido_trace_id == trace.trace_id
      assert metadata.jido_span_id == trace.span_id
    end

    test "caller metadata takes precedence over correlation metadata" do
      signal = Signal.new!("test.event.override", %{}, source: "/test")
      {_traced_signal, trace} = TraceContext.ensure_from_signal(signal)
      custom_trace_id = "custom-trace-id"

      Observe.emit_event([:jido, :test, :event], %{}, %{jido_trace_id: custom_trace_id})

      assert_receive {:event, [:jido, :test, :event], %{}, metadata}
      assert metadata.jido_trace_id == custom_trace_id
      assert metadata.jido_span_id == trace.span_id
    end
  end

  describe "redact/2" do
    test "returns value unchanged when redact_sensitive is false" do
      Application.put_env(:jido, :observability, redact_sensitive: false)
      assert Observe.redact("secret data") == "secret data"
    end

    test "returns [REDACTED] when redact_sensitive is true" do
      Application.put_env(:jido, :observability, redact_sensitive: true)
      assert Observe.redact("secret data") == "[REDACTED]"
    end

    test "returns value unchanged when redact_sensitive is not configured" do
      Application.put_env(:jido, :observability, [])
      assert Observe.redact("secret data") == "secret data"
    end

    test "returns value unchanged when observability config is not set" do
      Application.delete_env(:jido, :observability)
      assert Observe.redact("secret data") == "secret data"
    end

    test "force_redact: true always redacts regardless of config" do
      Application.put_env(:jido, :observability, redact_sensitive: false)
      assert Observe.redact("secret data", force_redact: true) == "[REDACTED]"
    end

    test "force_redact: false respects config" do
      Application.put_env(:jido, :observability, redact_sensitive: true)
      assert Observe.redact("secret data", force_redact: false) == "[REDACTED]"

      Application.put_env(:jido, :observability, redact_sensitive: false)
      assert Observe.redact("secret data", force_redact: false) == "secret data"
    end

    test "redacts various data types" do
      Application.put_env(:jido, :observability, redact_sensitive: true)

      assert Observe.redact(12_345) == "[REDACTED]"
      assert Observe.redact(%{key: "value"}) == "[REDACTED]"
      assert Observe.redact([:a, :b, :c]) == "[REDACTED]"
      assert Observe.redact(nil) == "[REDACTED]"
    end
  end

  describe "custom tracer with TestTracer" do
    setup do
      {:ok, _pid} = TestTracer.start_link()
      TestTracer.clear()
      Application.put_env(:jido, :observability, tracer: TestTracer)
      :ok
    end

    test "records span_start, span_stop through TestTracer" do
      span_ctx = Observe.start_span([:jido, :tracer, :test], %{key: "val"})
      Observe.finish_span(span_ctx, %{extra: 123})

      spans = TestTracer.get_spans()

      assert Enum.any?(spans, fn
               {:start, _ref, [:jido, :tracer, :test], %{key: "val"}} -> true
               _ -> false
             end)

      assert Enum.any?(spans, fn
               {:stop, _ref, %{duration: _, extra: 123}} -> true
               _ -> false
             end)
    end

    test "records span_exception through TestTracer" do
      span_ctx = Observe.start_span([:jido, :tracer, :exception], %{})
      Observe.finish_span_error(span_ctx, :error, :test_error, [])

      spans = TestTracer.get_spans()

      assert Enum.any?(spans, fn
               {:exception, _ref, :error, :test_error, []} -> true
               _ -> false
             end)
    end
  end

  describe "with_span catch clause" do
    setup do
      test_pid = self()
      handler_id = "catch-handler-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido, :test, :catch, :exception],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:exception_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "handles exit signals and re-exits" do
      Application.put_env(:jido, :observability, tracer: Jido.Observe.NoopTracer)

      assert catch_exit(
               Observe.with_span([:jido, :test, :catch], %{exit_test: true}, fn ->
                 exit(:test_exit_value)
               end)
             ) == :test_exit_value

      assert_receive {:exception_event, [:jido, :test, :catch, :exception], %{duration: _},
                      %{kind: :exit, error: :test_exit_value}}
    end
  end
end
