defmodule JidoTest.Observe.CompletionContractTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Observe

  defmodule OrderedTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event, metadata), do: metadata

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(ctx, kind, reason, stacktrace) do
      send(self(), {:completion, :tracer, kind, reason, stacktrace})

      case ctx.failure do
        :raise -> raise "tracer failed"
        :throw -> throw(:tracer_failed)
        :exit -> exit(:tracer_failed)
        nil -> :ok
      end
    end
  end

  defmodule TerminalFailureTracer do
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event, %{failure: failure}), do: failure

    @impl true
    def span_stop(:raise, _measurements), do: raise("terminal tracer failure")
    def span_stop(:throw, _measurements), do: throw(:terminal_tracer_failure)
    def span_stop(:exit, _measurements), do: exit(:terminal_tracer_failure)

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok
  end

  test "exception event precedes tracer completion and preserves raw arguments in both modes" do
    saved = Application.fetch_env(:jido, :observability)
    event = [:jido, :completion_contract, :exception]
    handler = {__MODULE__, make_ref()}

    :ok = :telemetry.attach(handler, event, &__MODULE__.capture_event/4, self())

    on_exit(fn ->
      :telemetry.detach(handler)

      case saved do
        {:ok, value} -> Application.put_env(:jido, :observability, value)
        :error -> Application.delete_env(:jido, :observability)
      end
    end)

    stacktrace = [{__MODULE__, :raw_frame, 2, [file: ~c"private/source.ex", line: 31]}]
    reason = %{password: "raw secret", reason: :failed}

    for mode <- [:warn, :strict],
        failure <- [nil, :raise, :throw, :exit],
        kind <- [:error, :throw, :exit] do
      Application.put_env(:jido, :observability,
        tracer: OrderedTracer,
        tracer_failure_mode: mode
      )

      span = Observe.start_span([:jido, :completion_contract], %{failure: failure})

      log =
        capture_log(fn ->
          if mode == :strict and failure != nil do
            assert_raise RuntimeError, fn ->
              Observe.finish_span_error(span, kind, reason, stacktrace)
            end
          else
            assert Observe.finish_span_error(span, kind, reason, stacktrace) == :ok
          end
        end)

      if mode == :warn and failure != nil, do: assert(log =~ "span_exception/4 failed")

      # The same mailbox pattern must consume the event before the tracer call.
      assert_received {:completion, source, first, second, metadata}
      assert source == :event
      assert first == event
      assert %{duration: duration} = second
      assert is_integer(duration)
      assert metadata.kind == kind
      assert_received {:completion, :tracer, ^kind, ^reason, ^stacktrace}
      refute_received {:completion, _, _, _, _}
    end
  end

  test "strict terminal tracer failures emit exactly one terminal event" do
    saved = Application.fetch_env(:jido, :observability)
    prefix = [:jido, :terminal_failure]
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [prefix ++ [:stop], prefix ++ [:exception]],
        fn event, _measurements, _metadata, pid -> send(pid, {:terminal, event}) end,
        self()
      )

    on_exit(fn ->
      :telemetry.detach(handler)

      case saved do
        {:ok, value} -> Application.put_env(:jido, :observability, value)
        :error -> Application.delete_env(:jido, :observability)
      end
    end)

    Application.put_env(:jido, :observability,
      tracer: TerminalFailureTracer,
      tracer_failure_mode: :strict
    )

    for failure <- [:raise, :throw, :exit] do
      assert_raise RuntimeError, ~r/tracer span_stop\/2 failed/, fn ->
        Observe.with_span(prefix, %{failure: failure}, fn -> :ok end)
      end

      assert_received {:terminal, event}
      assert event == prefix ++ [:stop]
      refute_received {:terminal, _event}
    end
  end

  def capture_event(event, measurements, metadata, pid) do
    send(pid, {:completion, :event, event, measurements, metadata})
  end
end
