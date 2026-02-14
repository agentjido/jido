defmodule JidoTest.Observe.OpenTelemetryTracerTest do
  use ExUnit.Case, async: false

  alias Jido.Observe.OpenTelemetryTracer

  defmodule FakeOpenTelemetry do
    @moduledoc false

    def get_application_tracer(app) do
      send(self(), {:otel_get_application_tracer, app})
      {:fake_tracer, app}
    end
  end

  defmodule FakeOtelTracer do
    @moduledoc false

    def current_span_ctx do
      send(self(), {:otel_current_span_ctx})
      :parent_ctx
    end

    def set_current_span(span_ctx) do
      send(self(), {:otel_set_current_span, span_ctx})
      :ok
    end

    def start_span(tracer, span_name, opts) do
      send(self(), {:otel_start_span, tracer, span_name, opts})
      :fake_span_ctx
    end
  end

  defmodule FakeOtelSpan do
    @moduledoc false

    def set_attributes(span_ctx, attrs) do
      send(self(), {:otel_set_attributes, span_ctx, attrs})
      :ok
    end

    def set_status(span_ctx, status, message) do
      send(self(), {:otel_set_status, span_ctx, status, message})
      :ok
    end

    def record_exception(span_ctx, kind, reason, stacktrace, attrs) do
      send(self(), {:otel_record_exception, span_ctx, kind, reason, stacktrace, attrs})
      :ok
    end

    def end_span(span_ctx) do
      send(self(), {:otel_end_span, span_ctx})
      :ok
    end
  end

  setup do
    original_modules = Application.get_env(:jido, :open_telemetry_tracer_modules)

    on_exit(fn ->
      if original_modules do
        Application.put_env(:jido, :open_telemetry_tracer_modules, original_modules)
      else
        Application.delete_env(:jido, :open_telemetry_tracer_modules)
      end
    end)

    :ok
  end

  test "no-ops when OpenTelemetry modules are unavailable" do
    Application.put_env(:jido, :open_telemetry_tracer_modules, %{
      opentelemetry: JidoTest.DoesNotExist.OpenTelemetry,
      otel_tracer: JidoTest.DoesNotExist.OtelTracer,
      otel_span: JidoTest.DoesNotExist.OtelSpan
    })

    assert OpenTelemetryTracer.span_start([:jido, :test, :span], %{request_id: "req-1"}) == nil
    assert OpenTelemetryTracer.span_stop(nil, %{duration: 1_000_000}) == :ok
    assert OpenTelemetryTracer.span_exception(nil, :error, :boom, []) == :ok
  end

  test "starts and stops spans with configured runtime modules" do
    Application.put_env(:jido, :open_telemetry_tracer_modules, %{
      opentelemetry: FakeOpenTelemetry,
      otel_tracer: FakeOtelTracer,
      otel_span: FakeOtelSpan
    })

    tracer_ctx =
      OpenTelemetryTracer.span_start(
        [:jido, :ai, :request],
        %{request_id: "req-1", status: :running, nested: %{x: 1}}
      )

    assert match?(%{span_ctx: :fake_span_ctx}, tracer_ctx)

    assert_receive {:otel_get_application_tracer, :jido}
    assert_receive {:otel_current_span_ctx}

    assert_receive {:otel_start_span, {:fake_tracer, :jido}, "jido.ai.request",
                    %{attributes: attrs}}

    assert {"request_id", "req-1"} in attrs
    assert {"status", "running"} in attrs
    assert {"nested", "%{x: 1}"} in attrs
    assert_receive {:otel_set_current_span, :fake_span_ctx}

    assert OpenTelemetryTracer.span_stop(tracer_ctx, %{duration: 3_000_000, tool_calls: 2}) == :ok

    assert_receive {:otel_set_attributes, :fake_span_ctx, attrs}
    assert {"duration_ms", 3} in attrs
    assert {"tool_calls", 2} in attrs
    assert_receive {:otel_end_span, :fake_span_ctx}
    assert_receive {:otel_set_current_span, :parent_ctx}
  end

  test "records exception status and details" do
    Application.put_env(:jido, :open_telemetry_tracer_modules, %{
      opentelemetry: FakeOpenTelemetry,
      otel_tracer: FakeOtelTracer,
      otel_span: FakeOtelSpan
    })

    tracer_ctx = OpenTelemetryTracer.span_start([:jido, :ai, :tool], %{tool: "search"})
    stacktrace = [{__MODULE__, :test, 0, []}]

    assert OpenTelemetryTracer.span_exception(tracer_ctx, :error, :tool_failed, stacktrace) == :ok

    assert_receive {:otel_set_status, :fake_span_ctx, :error, "error: :tool_failed"}

    assert_receive {:otel_record_exception, :fake_span_ctx, :error, :tool_failed, ^stacktrace,
                    attrs}

    assert {"jido.kind", "error"} in attrs
    assert_receive {:otel_end_span, :fake_span_ctx}
    assert_receive {:otel_set_current_span, :parent_ctx}
  end
end
