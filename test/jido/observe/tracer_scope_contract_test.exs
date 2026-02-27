defmodule JidoTest.Observe.TracerScopeContractTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Observe

  defmodule ScopedTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata) do
      send(self(), :legacy_start)
      :legacy_ctx
    end

    @impl true
    def span_stop(_ctx, _measurements) do
      send(self(), :legacy_stop)
      :ok
    end

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace) do
      send(self(), :legacy_exception)
      :ok
    end

    @impl true
    def with_span_scope(event_prefix, metadata, fun) do
      send(self(), {:scoped_called, event_prefix, metadata})
      fun.()
    end
  end

  defmodule LegacyTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(event_prefix, metadata) do
      send(self(), {:legacy_start, event_prefix, metadata})
      :legacy_ctx
    end

    @impl true
    def span_stop(ctx, measurements) do
      send(self(), {:legacy_stop, ctx, measurements})
      :ok
    end

    @impl true
    def span_exception(ctx, kind, reason, stacktrace) do
      send(self(), {:legacy_exception, ctx, kind, reason, stacktrace})
      :ok
    end
  end

  defmodule ZeroInvokeTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :ok

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok

    @impl true
    def with_span_scope(_event_prefix, _metadata, _fun), do: :ignored
  end

  defmodule DoubleInvokeTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :ok

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok

    @impl true
    def with_span_scope(_event_prefix, _metadata, fun) do
      first = fun.()
      _second = fun.()
      first
    end
  end

  defmodule TamperTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :ok

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok

    @impl true
    def with_span_scope(_event_prefix, _metadata, fun) do
      _ = fun.()
      :tampered
    end
  end

  defmodule SwallowTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :ok

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok

    @impl true
    def with_span_scope(_event_prefix, _metadata, fun) do
      try do
        fun.()
      rescue
        _ -> :swallowed
      catch
        _, _ -> :swallowed
      end
    end
  end

  defmodule ScopeThrowTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :ok

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok

    @impl true
    def with_span_scope(_event_prefix, _metadata, _fun) do
      throw(:scope_failure)
    end
  end

  defmodule PinnedTracerA do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata) do
      send(self(), :a_start)
      :a_ctx
    end

    @impl true
    def span_stop(ctx, measurements) do
      send(self(), {:a_stop, ctx, measurements})
      :ok
    end

    @impl true
    def span_exception(ctx, kind, reason, stacktrace) do
      send(self(), {:a_exception, ctx, kind, reason, stacktrace})
      :ok
    end
  end

  defmodule PinnedTracerB do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata) do
      send(self(), :b_start)
      :b_ctx
    end

    @impl true
    def span_stop(ctx, measurements) do
      send(self(), {:b_stop, ctx, measurements})
      :ok
    end

    @impl true
    def span_exception(ctx, kind, reason, stacktrace) do
      send(self(), {:b_exception, ctx, kind, reason, stacktrace})
      :ok
    end
  end

  defmodule ThrowingFinishTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :finish_ctx

    @impl true
    def span_stop(_ctx, _measurements), do: throw(:stop_throw)

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: exit(:exception_exit)
  end

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

  test "with_span/3 uses with_span_scope/3 when implemented" do
    Application.put_env(:jido, :observability, tracer: ScopedTracer)

    assert :ok =
             Observe.with_span([:jido, :scope, :used], %{mode: :scoped}, fn ->
               :ok
             end)

    assert_receive {:scoped_called, [:jido, :scope, :used], %{mode: :scoped}}
    refute_receive :legacy_start, 10
    refute_receive :legacy_stop, 10
    refute_receive :legacy_exception, 10
  end

  test "with_span/3 falls back to legacy callbacks when scoped callback is missing" do
    Application.put_env(:jido, :observability, tracer: LegacyTracer)

    assert :ok =
             Observe.with_span([:jido, :scope, :legacy], %{mode: :legacy}, fn ->
               :ok
             end)

    assert_receive {:legacy_start, [:jido, :scope, :legacy], %{mode: :legacy}}
    assert_receive {:legacy_stop, :legacy_ctx, %{duration: _}}
  end

  test "warn mode executes wrapped function when scoped callback never invokes it" do
    Application.put_env(:jido, :observability, tracer: ZeroInvokeTracer)

    log =
      capture_log(fn ->
        assert :expected =
                 Observe.with_span([:jido, :scope, :zero], %{}, fn ->
                   :expected
                 end)
      end)

    assert log =~ "with_span_scope/3 contract violation"
    assert log =~ "did not invoke wrapped function"
  end

  test "strict mode raises when scoped callback never invokes wrapped function" do
    Application.put_env(
      :jido,
      :observability,
      tracer: ZeroInvokeTracer,
      tracer_failure_mode: :strict
    )

    assert_raise RuntimeError, ~r/did not invoke wrapped function/, fn ->
      Observe.with_span([:jido, :scope, :zero, :strict], %{}, fn ->
        :ok
      end)
    end
  end

  test "warn mode preserves first invocation result when scoped callback calls wrapped function twice" do
    Application.put_env(:jido, :observability, tracer: DoubleInvokeTracer)

    log =
      capture_log(fn ->
        assert :first =
                 Observe.with_span([:jido, :scope, :double], %{}, fn ->
                   :first
                 end)
      end)

    assert log =~ "invoked wrapped function more than once"
  end

  test "strict mode raises when scoped callback calls wrapped function twice" do
    Application.put_env(
      :jido,
      :observability,
      tracer: DoubleInvokeTracer,
      tracer_failure_mode: :strict
    )

    assert_raise RuntimeError, ~r/strict mode rejected scoped callback contract violations/, fn ->
      Observe.with_span([:jido, :scope, :double, :strict], %{}, fn ->
        :ok
      end)
    end
  end

  test "warn mode preserves wrapped function return value when callback tampers with return" do
    Application.put_env(:jido, :observability, tracer: TamperTracer)

    log =
      capture_log(fn ->
        assert {:ok, :expected} =
                 Observe.with_span([:jido, :scope, :tamper], %{}, fn ->
                   {:ok, :expected}
                 end)
      end)

    assert log =~ "did not preserve wrapped function return value"
  end

  test "strict mode raises when callback tampers with return" do
    Application.put_env(
      :jido,
      :observability,
      tracer: TamperTracer,
      tracer_failure_mode: :strict
    )

    assert_raise RuntimeError, ~r/strict mode rejected scoped callback contract violations/, fn ->
      Observe.with_span([:jido, :scope, :tamper, :strict], %{}, fn ->
        :ok
      end)
    end
  end

  test "swallowed error is re-raised from wrapped function" do
    Application.put_env(:jido, :observability, tracer: SwallowTracer)

    log =
      capture_log(fn ->
        assert_raise RuntimeError, "scope boom", fn ->
          Observe.with_span([:jido, :scope, :swallow, :error], %{}, fn ->
            raise "scope boom"
          end)
        end
      end)

    assert log =~ "swallowed wrapped function exception"
  end

  test "swallowed throw is re-thrown from wrapped function" do
    Application.put_env(:jido, :observability, tracer: SwallowTracer)

    assert catch_throw(
             Observe.with_span([:jido, :scope, :swallow, :throw], %{}, fn ->
               throw(:scope_throw)
             end)
           ) == :scope_throw
  end

  test "swallowed exit is re-exited from wrapped function" do
    Application.put_env(:jido, :observability, tracer: SwallowTracer)

    assert catch_exit(
             Observe.with_span([:jido, :scope, :swallow, :exit], %{}, fn ->
               exit(:scope_exit)
             end)
           ) == :scope_exit
  end

  test "warn mode falls back to wrapped function when scoped callback throws before invocation" do
    Application.put_env(:jido, :observability, tracer: ScopeThrowTracer)

    log =
      capture_log(fn ->
        assert :ok =
                 Observe.with_span([:jido, :scope, :throw, :warn], %{}, fn ->
                   :ok
                 end)
      end)

    assert log =~ "tracer with_span_scope/3 failed"
    assert log =~ "scope_failure"
  end

  test "strict mode raises when scoped callback throws before invocation" do
    Application.put_env(
      :jido,
      :observability,
      tracer: ScopeThrowTracer,
      tracer_failure_mode: :strict
    )

    assert_raise RuntimeError, ~r/tracer with_span_scope\/3 failed/, fn ->
      Observe.with_span([:jido, :scope, :throw, :strict], %{}, fn ->
        :ok
      end)
    end
  end

  test "finish_span uses tracer pinned at start even if config changes" do
    Application.put_env(:jido, :observability, tracer: PinnedTracerA)
    span_ctx = Observe.start_span([:jido, :scope, :pinned], %{})

    Application.put_env(:jido, :observability, tracer: PinnedTracerB)

    assert :ok = Observe.finish_span(span_ctx)

    assert_receive :a_start
    assert_receive {:a_stop, :a_ctx, %{duration: _}}
    refute_receive {:b_stop, _, _}, 10
  end

  test "warn mode isolates throw/exit in finish callbacks" do
    Application.put_env(:jido, :observability, tracer: ThrowingFinishTracer)

    log =
      capture_log(fn ->
        span_ctx = Observe.start_span([:jido, :scope, :finish, :warn], %{})
        assert :ok = Observe.finish_span(span_ctx)

        error_ctx = Observe.start_span([:jido, :scope, :finish, :warn, :exception], %{})
        assert :ok = Observe.finish_span_error(error_ctx, :error, :reason, [])
      end)

    assert log =~ "tracer span_stop/2 failed"
    assert log =~ "tracer span_exception/4 failed"
  end

  test "strict mode raises on throw/exit in finish callbacks" do
    Application.put_env(
      :jido,
      :observability,
      tracer: ThrowingFinishTracer,
      tracer_failure_mode: :strict
    )

    stop_ctx = Observe.start_span([:jido, :scope, :finish, :strict], %{})

    assert_raise RuntimeError, ~r/tracer span_stop\/2 failed/, fn ->
      Observe.finish_span(stop_ctx)
    end

    exception_ctx = Observe.start_span([:jido, :scope, :finish, :strict, :exception], %{})

    assert_raise RuntimeError, ~r/tracer span_exception\/4 failed/, fn ->
      Observe.finish_span_error(exception_ctx, :error, :reason, [])
    end
  end
end
