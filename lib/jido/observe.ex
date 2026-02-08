defmodule Jido.Observe do
  @moduledoc """
  Unified observability façade for Jido agents.

  Wraps `:telemetry` events and `Logger` with a simple API for observing
  agent execution, action invocations, and workflow iterations.

  ## Features

  - Automatic telemetry event emission (start/stop/exception)
  - Duration measurement for all spans (nanoseconds)
  - Automatic correlation ID enrichment from `Jido.Tracing.Context`
  - Extension point for future OpenTelemetry integration via `Jido.Observe.Tracer`
  - Threshold-based logging via `Jido.Observe.Log`

  ## Correlation Tracing Integration

  When `Jido.Tracing.Context` has an active trace context (set via signal processing),
  all spans automatically include correlation metadata:

  - `:jido_trace_id` - shared trace identifier across the call chain
  - `:jido_span_id` - unique span identifier for the current signal
  - `:jido_parent_span_id` - parent span that triggered this signal
  - `:jido_causation_id` - signal ID that caused this signal

  This connects timed telemetry spans with signal causation tracking automatically.

  ## Configuration

      config :jido, :observability,
        log_level: :info,
        tracer: Jido.Observe.NoopTracer

  ## Usage

  ### Synchronous work

      Jido.Observe.with_span([:jido, :agent, :action, :run], %{agent_id: id, action: "my_action"}, fn ->
        # Your code here
        {:ok, result}
      end)

  ### Asynchronous work (Tasks)

      span_ctx = Jido.Observe.start_span([:jido, :agent, :async, :request], %{agent_id: id})

      Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
        try do
          result = do_async_work()
          Jido.Observe.finish_span(span_ctx, %{result_size: byte_size(result)})
          result
        rescue
          e ->
            Jido.Observe.finish_span_error(span_ctx, :error, e, __STACKTRACE__)
            reraise e, __STACKTRACE__
        end
      end)

  ## Telemetry Events

  All spans emit standard telemetry events:

  - `event_prefix ++ [:start]` - emitted when span starts
  - `event_prefix ++ [:stop]` - emitted on successful completion
  - `event_prefix ++ [:exception]` - emitted on error

  Measurements include:
  - `:system_time` - start timestamp (nanoseconds)
  - `:duration` - elapsed time (nanoseconds, on stop/exception)
  - Any additional measurements passed to `finish_span/2`

  ## Metadata Best Practices

  Metadata should be small, identifying data (IDs, step numbers, model names), not full
  prompts/responses. For large payloads, include derived measurements (`prompt_tokens`,
  `prompt_size_bytes`) rather than the raw content.
  """

  require Logger

  alias Jido.Observe.Log
  alias Jido.Observe.SpanCtx
  alias Jido.Tracing.Context, as: TracingContext

  @type event_prefix :: [atom()]
  @type metadata :: map()
  @type measurements :: map()
  @type span_ctx :: SpanCtx.t()

  @doc """
  Wraps synchronous work with telemetry span events.

  Emits `:start` event before executing the function, then either `:stop` on
  success or `:exception` if an error is raised. Duration is automatically measured.

  ## Parameters

  - `event_prefix` - List of atoms for the telemetry event name (e.g., `[:jido, :ai, :react, :step]`)
  - `metadata` - Map of metadata to include in all events
  - `fun` - Zero-arity function to execute

  ## Returns

  The return value of `fun`.

  ## Example

      Jido.Observe.with_span([:jido, :ai, :tool, :invoke], %{tool: "search"}, fn ->
        perform_search(query)
      end)
  """
  @spec with_span(event_prefix(), metadata(), (-> result)) :: result when result: term()
  def with_span(event_prefix, metadata, fun)
      when is_list(event_prefix) and is_map(metadata) and is_function(fun, 0) do
    span_ctx = start_span(event_prefix, metadata)

    try do
      result = fun.()
      finish_span(span_ctx)
      result
    rescue
      e ->
        finish_span_error(span_ctx, :error, e, __STACKTRACE__)
        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        finish_span_error(span_ctx, kind, reason, __STACKTRACE__)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Starts an async span for work that will complete later.

  Use this for Task-based operations where you can't use `with_span/3`.
  You must call `finish_span/2` or `finish_span_error/4` when the work completes.

  ## Parameters

  - `event_prefix` - List of atoms for the telemetry event name
  - `metadata` - Map of metadata to include in all events

  ## Returns

  A span context struct to pass to `finish_span/2` or `finish_span_error/4`.

  ## Example

      span_ctx = Jido.Observe.start_span([:jido, :ai, :llm, :request], %{model: "claude"})

      Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
        result = do_work()
        Jido.Observe.finish_span(span_ctx, %{output_bytes: byte_size(result)})
      end)
  """
  @spec start_span(event_prefix(), metadata()) :: span_ctx()
  def start_span(event_prefix, metadata) when is_list(event_prefix) and is_map(metadata) do
    start_time = System.monotonic_time(:nanosecond)
    start_system_time = System.system_time(:nanosecond)

    enriched_metadata = enrich_with_correlation(metadata)

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: start_system_time},
      enriched_metadata
    )

    tracer_ctx =
      try do
        tracer().span_start(event_prefix, enriched_metadata)
      rescue
        e ->
          Logger.warning("Jido.Observe tracer span_start/2 failed: #{inspect(e)}")
          nil
      end

    %SpanCtx{
      event_prefix: event_prefix,
      start_time: start_time,
      start_system_time: start_system_time,
      metadata: enriched_metadata,
      tracer_ctx: tracer_ctx
    }
  end

  @doc """
  Finishes a span successfully.

  ## Parameters

  - `span_ctx` - The span context returned by `start_span/2`
  - `extra_measurements` - Additional measurements to include (e.g., token counts)

  ## Example

      Jido.Observe.finish_span(span_ctx, %{prompt_tokens: 100, completion_tokens: 50})
  """
  @spec finish_span(span_ctx(), measurements()) :: :ok
  def finish_span(span_ctx, extra_measurements \\ %{})

  def finish_span(%SpanCtx{} = span_ctx, extra_measurements) when is_map(extra_measurements) do
    %SpanCtx{
      event_prefix: event_prefix,
      start_time: start_time,
      metadata: metadata,
      tracer_ctx: tracer_ctx
    } = span_ctx

    duration = System.monotonic_time(:nanosecond) - start_time

    measurements = Map.merge(%{duration: duration}, extra_measurements)

    :telemetry.execute(
      event_prefix ++ [:stop],
      measurements,
      metadata
    )

    try do
      tracer().span_stop(tracer_ctx, measurements)
    rescue
      e ->
        Logger.warning("Jido.Observe tracer span_stop/2 failed: #{inspect(e)}")
    end

    :ok
  end

  @doc """
  Finishes a span with an error.

  ## Parameters

  - `span_ctx` - The span context returned by `start_span/2`
  - `kind` - The error kind (`:error`, `:exit`, `:throw`)
  - `reason` - The error reason/exception
  - `stacktrace` - The stacktrace

  ## Example

      rescue
        e ->
          Jido.Observe.finish_span_error(span_ctx, :error, e, __STACKTRACE__)
          reraise e, __STACKTRACE__
  """
  @spec finish_span_error(span_ctx(), atom(), term(), list()) :: :ok
  def finish_span_error(%SpanCtx{} = span_ctx, kind, reason, stacktrace) do
    %SpanCtx{
      event_prefix: event_prefix,
      start_time: start_time,
      metadata: metadata,
      tracer_ctx: tracer_ctx
    } = span_ctx

    duration = System.monotonic_time(:nanosecond) - start_time

    error_metadata =
      Map.merge(metadata, %{
        kind: kind,
        error: reason,
        stacktrace: stacktrace
      })

    :telemetry.execute(
      event_prefix ++ [:exception],
      %{duration: duration},
      error_metadata
    )

    try do
      tracer().span_exception(tracer_ctx, kind, reason, stacktrace)
    rescue
      e ->
        Logger.warning("Jido.Observe tracer span_exception/4 failed: #{inspect(e)}")
    end

    :ok
  end

  @doc """
  Conditionally logs a message based on the observability threshold.

  Delegates to `Jido.Observe.Log.log/3`.

  ## Example

      Jido.Observe.log(:debug, "Processing step", agent_id: agent.id)
  """
  @spec log(Logger.level(), Logger.message(), keyword()) :: :ok
  def log(level, message, metadata \\ []) do
    Log.log(level, message, metadata)
  end

  @doc """
  Emits a debug event only if debug events are enabled in config.

  This helper checks the `:debug_events` config before emitting, ensuring
  zero overhead when debugging is disabled (production default).

  ## Configuration

      # config/dev.exs
      config :jido, :observability,
        debug_events: :all  # or :minimal, :off

      # config/prod.exs
      config :jido, :observability,
        debug_events: :off

  ## Parameters

  - `event_prefix` - Telemetry event name
  - `measurements` - Map of measurements (durations, counts, etc.)
  - `metadata` - Map of metadata (agent_id, iteration, etc.)

  ## Example

      Jido.Observe.emit_debug_event(
        [:jido, :agent, :iteration, :stop],
        %{duration: 1_234_567},
        %{agent_id: agent.id, iteration: 3, status: :awaiting_tool}
      )
  """
  @spec emit_debug_event(event_prefix(), measurements(), metadata()) :: :ok
  def emit_debug_event(event_prefix, measurements \\ %{}, metadata \\ %{}) do
    if debug_enabled?() do
      :telemetry.execute(event_prefix, measurements, metadata)
    end

    :ok
  end

  @doc """
  Checks if debug events are enabled in configuration.

  ## Returns

  `true` if `:debug_events` is `:all` or `:minimal`, `false` otherwise.
  """
  @spec debug_enabled?() :: boolean()
  def debug_enabled? do
    case observability_config()[:debug_events] do
      :off -> false
      nil -> false
      _ -> true
    end
  end

  @doc """
  Redacts sensitive data based on configuration.

  When `:redact_sensitive` is true (production default), replaces the value
  with `"[REDACTED]"`. Otherwise returns the value unchanged.

  ## Configuration

      # config/prod.exs
      config :jido, :observability,
        redact_sensitive: true

      # config/dev.exs
      config :jido, :observability,
        redact_sensitive: false

  ## Parameters

  - `value` - The value to potentially redact
  - `opts` - Optional keyword list with `:force_redact` override

  ## Examples

      # In production (redact_sensitive: true)
      redact("secret data")
      # => "[REDACTED]"

      # In development (redact_sensitive: false)
      redact("secret data")
      # => "secret data"

      # Force redaction regardless of config
      redact("secret data", force_redact: true)
      # => "[REDACTED]"
  """
  @spec redact(term(), keyword()) :: term()
  def redact(value, opts \\ []) do
    force_redact = Keyword.get(opts, :force_redact, false)
    should_redact = force_redact || observability_config()[:redact_sensitive] == true

    if should_redact do
      "[REDACTED]"
    else
      value
    end
  end

  defp tracer do
    observability_config()
    |> Keyword.get(:tracer, Jido.Observe.NoopTracer)
  end

  @doc false
  @spec observability_config() :: keyword()
  def observability_config do
    Application.get_env(:jido, :observability, [])
  end

  defp enrich_with_correlation(metadata) do
    case correlation_metadata() do
      empty when empty == %{} -> metadata
      correlation -> Map.merge(correlation, metadata)
    end
  end

  defp correlation_metadata do
    if Code.ensure_loaded?(TracingContext) do
      TracingContext.to_telemetry_metadata()
    else
      %{}
    end
  end
end
