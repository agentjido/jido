defmodule JidoTest.ObserveTest do
  @moduledoc """
  Tests for Jido.Observe façade and related modules.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Observe
  alias Jido.Observe.Log
  alias Jido.Observe.NoopTracer

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :debug)

    on_exit(fn ->
      Logger.configure(level: previous_level)
    end)

    :ok
  end

  describe "with_span/3" do
    setup do
      test_pid = self()
      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :test, :with_span, :start],
          [:jido, :test, :with_span, :stop],
          [:jido, :test, :with_span, :exception]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits :start and :stop telemetry events" do
      result =
        Observe.with_span([:jido, :test, :with_span], %{key: "value"}, fn ->
          :success
        end)

      assert result == :success

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :start], %{system_time: st},
                      %{key: "value"}}

      assert is_integer(st)

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :stop], %{duration: duration},
                      %{key: "value"}}

      assert is_integer(duration)
      assert duration >= 0
    end

    test "returns the function's return value" do
      result =
        Observe.with_span([:jido, :test, :with_span], %{}, fn ->
          {:ok, %{data: [1, 2, 3]}}
        end)

      assert result == {:ok, %{data: [1, 2, 3]}}
    end

    test "measures duration correctly" do
      sleep_time_ms = 10

      Observe.with_span([:jido, :test, :with_span], %{}, fn ->
        Process.sleep(sleep_time_ms)
      end)

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :stop], %{duration: duration},
                      _}

      duration_ms = div(duration, 1_000_000)
      assert duration_ms >= sleep_time_ms
    end

    test "emits :exception event on error and re-raises" do
      assert_raise RuntimeError, "test error", fn ->
        Observe.with_span([:jido, :test, :with_span], %{error_test: true}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :start], _,
                      %{error_test: true}}

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :exception],
                      %{duration: duration}, metadata}

      assert is_integer(duration)
      assert duration >= 0
      assert metadata.error_test == true
      assert metadata.kind == :error
      assert %RuntimeError{message: "test error"} = metadata.error
      assert is_list(metadata.stacktrace)
    end

    test "emits :exception event on throw and re-throws" do
      assert catch_throw(
               Observe.with_span([:jido, :test, :with_span], %{throw_test: true}, fn ->
                 throw(:my_throw)
               end)
             ) == :my_throw

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :start], _,
                      %{throw_test: true}}

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :exception], %{duration: _},
                      metadata}

      assert metadata.kind == :throw
      assert metadata.error == :my_throw
    end

    test "emits :exception event on exit and re-exits" do
      assert catch_exit(
               Observe.with_span([:jido, :test, :with_span], %{exit_test: true}, fn ->
                 exit(:my_exit)
               end)
             ) == :my_exit

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :start], _, %{exit_test: true}}

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :exception], %{duration: _},
                      metadata}

      assert metadata.kind == :exit
      assert metadata.error == :my_exit
    end

    test "passes metadata to all events" do
      metadata = %{agent_id: "agent-123", step: 5, model: "claude"}

      Observe.with_span([:jido, :test, :with_span], metadata, fn ->
        :ok
      end)

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :start], _, received_metadata}
      assert received_metadata == metadata

      assert_receive {:telemetry_event, [:jido, :test, :with_span, :stop], _, received_metadata}
      assert received_metadata == metadata
    end
  end

  describe "start_span/2 and finish_span/2" do
    setup do
      test_pid = self()
      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :test, :manual_span, :start],
          [:jido, :test, :manual_span, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits :start event on start_span" do
      _span_ctx = Observe.start_span([:jido, :test, :manual_span], %{key: "start_value"})

      assert_receive {:telemetry_event, [:jido, :test, :manual_span, :start], %{system_time: st},
                      %{key: "start_value"}}

      assert is_integer(st)
    end

    test "emits :stop event on finish_span" do
      span_ctx = Observe.start_span([:jido, :test, :manual_span], %{key: "stop_value"})
      result = Observe.finish_span(span_ctx)

      assert result == :ok

      assert_receive {:telemetry_event, [:jido, :test, :manual_span, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :test, :manual_span, :stop],
                      %{duration: duration}, %{key: "stop_value"}}

      assert is_integer(duration)
      assert duration >= 0
    end

    test "includes extra_measurements in stop event" do
      span_ctx = Observe.start_span([:jido, :test, :manual_span], %{})

      extra = %{prompt_tokens: 100, completion_tokens: 50, total_tokens: 150}
      Observe.finish_span(span_ctx, extra)

      assert_receive {:telemetry_event, [:jido, :test, :manual_span, :stop], measurements, _}

      assert measurements.duration >= 0
      assert measurements.prompt_tokens == 100
      assert measurements.completion_tokens == 50
      assert measurements.total_tokens == 150
    end

    test "duration is measured correctly" do
      sleep_time_ms = 10

      span_ctx = Observe.start_span([:jido, :test, :manual_span], %{})
      Process.sleep(sleep_time_ms)
      Observe.finish_span(span_ctx)

      assert_receive {:telemetry_event, [:jido, :test, :manual_span, :stop],
                      %{duration: duration}, _}

      duration_ms = div(duration, 1_000_000)
      assert duration_ms >= sleep_time_ms
    end

    test "returns span context struct with required keys" do
      span_ctx = Observe.start_span([:jido, :test, :manual_span], %{meta: "data"})

      assert %Jido.Observe.SpanCtx{} = span_ctx
      assert span_ctx.event_prefix == [:jido, :test, :manual_span]
      assert span_ctx.metadata == %{meta: "data"}
      assert is_integer(span_ctx.start_time)
      assert is_integer(span_ctx.start_system_time)
    end
  end

  describe "finish_span_error/4" do
    setup do
      test_pid = self()
      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :test, :error_span, :start],
          [:jido, :test, :error_span, :exception]
        ],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_id)
      end)

      :ok
    end

    test "emits :exception event" do
      span_ctx = Observe.start_span([:jido, :test, :error_span], %{})

      result =
        Observe.finish_span_error(
          span_ctx,
          :error,
          %RuntimeError{message: "boom"},
          [{__MODULE__, :test, 0, []}]
        )

      assert result == :ok

      assert_receive {:telemetry_event, [:jido, :test, :error_span, :exception], %{duration: _},
                      _}
    end

    test "includes kind, error, stacktrace in metadata" do
      span_ctx = Observe.start_span([:jido, :test, :error_span], %{original: "meta"})

      error = %ArgumentError{message: "invalid argument"}
      stacktrace = [{__MODULE__, :some_fun, 2, [file: ~c"test.ex", line: 42]}]

      Observe.finish_span_error(span_ctx, :error, error, stacktrace)

      assert_receive {:telemetry_event, [:jido, :test, :error_span, :exception], %{duration: _},
                      metadata}

      assert metadata.original == "meta"
      assert metadata.kind == :error
      assert metadata.error == error
      assert metadata.stacktrace == stacktrace
    end

    test "supports different error kinds" do
      for kind <- [:error, :exit, :throw] do
        span_ctx = Observe.start_span([:jido, :test, :error_span], %{})
        Observe.finish_span_error(span_ctx, kind, :some_reason, [])

        assert_receive {:telemetry_event, [:jido, :test, :error_span, :exception], _,
                        %{kind: ^kind}}
      end
    end

    test "measures duration correctly" do
      sleep_time_ms = 10

      span_ctx = Observe.start_span([:jido, :test, :error_span], %{})
      Process.sleep(sleep_time_ms)
      Observe.finish_span_error(span_ctx, :error, :some_error, [])

      assert_receive {:telemetry_event, [:jido, :test, :error_span, :exception],
                      %{duration: duration}, _}

      duration_ms = div(duration, 1_000_000)
      assert duration_ms >= sleep_time_ms
    end
  end

  describe "log/3" do
    setup do
      original_config = Application.get_env(:jido, :observability)

      on_exit(fn ->
        if original_config do
          Application.put_env(:jido, :observability, original_config)
        else
          Application.delete_env(:jido, :observability)
        end
      end)

      :ok
    end

    test "delegates to Jido.Observe.Log" do
      Application.put_env(:jido, :observability, log_level: :debug)

      log =
        capture_log(fn ->
          Observe.log(:info, "test message", key: "value")
        end)

      assert log =~ "test message"
    end
  end

  describe "Jido.Observe.Log.threshold/0" do
    setup do
      original_config = Application.get_env(:jido, :observability)

      on_exit(fn ->
        if original_config do
          Application.put_env(:jido, :observability, original_config)
        else
          Application.delete_env(:jido, :observability)
        end
      end)

      :ok
    end

    test "returns configured value" do
      Application.put_env(:jido, :observability, log_level: :warning)
      assert Log.threshold() == :warning

      Application.put_env(:jido, :observability, log_level: :debug)
      assert Log.threshold() == :debug
    end

    test "defaults to :info when not configured" do
      Application.delete_env(:jido, :observability)
      assert Log.threshold() == :info
    end

    test "defaults to :info when log_level key is missing" do
      Application.put_env(:jido, :observability, tracer: SomeTracer)
      assert Log.threshold() == :info
    end

    test "defaults to :info when configured log_level is invalid" do
      Application.put_env(:jido, :observability, log_level: :verbose)
      assert Log.threshold() == :info
    end
  end

  describe "Jido.Observe.Log.log/3" do
    setup do
      original_config = Application.get_env(:jido, :observability)

      on_exit(fn ->
        if original_config do
          Application.put_env(:jido, :observability, original_config)
        else
          Application.delete_env(:jido, :observability)
        end
      end)

      :ok
    end

    test "logs when message level meets threshold" do
      Application.put_env(:jido, :observability, log_level: :info)

      log =
        capture_log(fn ->
          Log.log(:info, "info message")
        end)

      assert log =~ "info message"
    end

    test "logs when message level exceeds threshold" do
      Application.put_env(:jido, :observability, log_level: :info)

      log =
        capture_log(fn ->
          Log.log(:warning, "warning message")
        end)

      assert log =~ "warning message"
    end

    test "does not log when message level is below threshold" do
      Application.put_env(:jido, :observability, log_level: :warning)

      log =
        capture_log(fn ->
          Log.log(:debug, "debug message")
          Log.log(:info, "info message")
        end)

      refute log =~ "debug message"
      refute log =~ "info message"
    end

    test "includes metadata in log output" do
      Application.put_env(:jido, :observability, log_level: :debug)

      log =
        capture_log(fn ->
          Log.log(:info, "with metadata", agent_id: "agent-123")
        end)

      assert log =~ "with metadata"
    end

    test "logs at debug level when threshold is debug" do
      Application.put_env(:jido, :observability, log_level: :debug)

      log =
        capture_log(fn ->
          Log.log(:debug, "debug level message")
        end)

      assert log =~ "debug level message"
    end

    test "treats :trace threshold as most verbose level" do
      Application.put_env(:jido, :observability, log_level: :trace)

      log =
        capture_log(fn ->
          Log.log(:debug, "trace threshold debug message")
        end)

      assert log =~ "trace threshold debug message"
    end
  end

  describe "Jido.Observe.NoopTracer" do
    test "span_start/2 returns nil" do
      result = NoopTracer.span_start([:jido, :test], %{key: "value"})
      assert result == nil
    end

    test "span_stop/2 returns :ok" do
      result = NoopTracer.span_stop(nil, %{duration: 1000})
      assert result == :ok
    end

    test "span_exception/4 returns :ok" do
      result =
        NoopTracer.span_exception(
          nil,
          :error,
          %RuntimeError{message: "error"},
          []
        )

      assert result == :ok
    end

    test "implements Jido.Observe.Tracer behaviour" do
      behaviours = NoopTracer.__info__(:attributes)[:behaviour]
      assert Jido.Observe.Tracer in behaviours
    end
  end

  describe "custom tracer integration" do
    setup do
      original_config = Application.get_env(:jido, :observability)

      on_exit(fn ->
        if original_config do
          Application.put_env(:jido, :observability, original_config)
        else
          Application.delete_env(:jido, :observability)
        end
      end)

      :ok
    end

    test "uses configured tracer for span operations" do
      defmodule TestTracer do
        @behaviour Jido.Observe.Tracer

        def span_start(event_prefix, metadata) do
          send(self(), {:tracer_start, event_prefix, metadata})
          :test_ctx
        end

        def span_stop(tracer_ctx, measurements) do
          send(self(), {:tracer_stop, tracer_ctx, measurements})
          :ok
        end

        def span_exception(tracer_ctx, kind, reason, stacktrace) do
          send(self(), {:tracer_exception, tracer_ctx, kind, reason, stacktrace})
          :ok
        end
      end

      Application.put_env(:jido, :observability, tracer: TestTracer)

      Observe.with_span([:jido, :custom], %{test: true}, fn ->
        :result
      end)

      assert_receive {:tracer_start, [:jido, :custom], %{test: true}}
      assert_receive {:tracer_stop, :test_ctx, %{duration: _}}
    end
  end
end
