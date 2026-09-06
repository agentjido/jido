defmodule JidoCoreBench.ObserveInstance do
  @moduledoc false
  def __otp_app__, do: :jido
end

defmodule JidoCoreBench.LegacyTracer do
  @moduledoc false
  @behaviour Jido.Observe.Tracer
  @impl true
  def span_start(_event, _metadata), do: :bench_span
  @impl true
  def span_stop(:bench_span, _measurements), do: :ok
  @impl true
  def span_exception(:bench_span, _kind, _reason, _stacktrace), do: :ok
end

defmodule JidoCoreBench.ScopedTracer do
  @moduledoc false
  @behaviour Jido.Observe.Tracer
  @impl true
  def span_start(_event, _metadata), do: raise("scoped benchmark called legacy start")
  @impl true
  def span_stop(_context, _measurements), do: raise("scoped benchmark called legacy stop")
  @impl true
  def span_exception(_context, _kind, _reason, _stacktrace),
    do: raise("scoped benchmark called legacy exception")

  @impl true
  def with_span_scope(_event, _metadata, fun), do: fun.()
end

defmodule JidoCoreBench.ObserveCases do
  @moduledoc false
  alias Jido.Tracing.Context, as: TraceContext
  alias JidoCoreBench.{Fixtures, ObserveInstance}

  def workloads do
    for {name, tracer} <- [
          noop: Jido.Observe.NoopTracer,
          legacy: JidoCoreBench.LegacyTracer,
          scoped: JidoCoreBench.ScopedTracer
        ],
        correlated <- [false, true],
        size <- [0, 1_000] do
      Fixtures.checked(
        "observe/batch/#{name}/correlation_#{correlated}/metadata_#{size}/100",
        fn _ -> setup(tracer, correlated, size) end,
        fn prepared ->
          count =
            Enum.reduce(1..100, 0, fn _, count ->
              Jido.Observe.with_span([:jido, :bench], prepared.metadata, fn -> count + 1 end)
            end)

          {count, TraceContext.to_telemetry_metadata()}
        end,
        fn {count, _trace} -> Fixtures.equal!(count, 100) end
      )
      |> Map.put(:verify, fn p, {100, trace} -> Fixtures.equal!(trace, p.trace) end)
      |> Map.put(:cleanup, &cleanup/1)
    end
  end

  defp setup(tracer, correlated, size) do
    previous = Application.fetch_env(:jido, ObserveInstance)

    Application.put_env(:jido, ObserveInstance,
      observability: [tracer: tracer, tracer_failure_mode: :strict]
    )

    Fixtures.equal!(Jido.Observe.Config.tracer(ObserveInstance), tracer)
    if correlated, do: TraceContext.ensure_from_signal(Fixtures.signal())

    metadata =
      Map.new(1..size//1, &{"key-#{&1}", &1})
      |> Map.put(:jido_instance, ObserveInstance)

    %{previous: previous, metadata: metadata, trace: TraceContext.to_telemetry_metadata()}
  end

  defp cleanup(prepared) do
    TraceContext.clear()

    case prepared.previous do
      {:ok, value} -> Application.put_env(:jido, ObserveInstance, value)
      :error -> Application.delete_env(:jido, ObserveInstance)
    end
  end
end
