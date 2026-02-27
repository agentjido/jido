defmodule Jido.Observe do
  @moduledoc """
  Unified observability facade for Jido agents.

  Wraps `:telemetry` events and `Logger` with a simple API for observing
  agent execution, action invocations, and workflow iterations.

  ## Features

  - Automatic telemetry event emission (start/stop/exception)
  - Duration measurement for all spans (nanoseconds)
  - Automatic correlation ID enrichment from `Jido.Tracing.Context`
  - Pluggable tracer callbacks via `Jido.Observe.Tracer`
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
        tracer: Jido.Observe.NoopTracer,
        tracer_failure_mode: :warn

  `:tracer_failure_mode` controls tracer callback errors:

  - `:warn` (default) isolates tracer failures and logs warnings
  - `:strict` raises immediately on tracer callback failures

  ## Usage

  ### Synchronous work

      Jido.Observe.with_span([:jido, :agent, :action, :run], %{agent_id: id, action: "my_action"}, fn ->
        # Your code here
        {:ok, result}
      end)

  If the configured tracer implements optional `with_span_scope/3`, `with_span/3`
  uses that callback for sync span scoping. Adapter contract for `with_span_scope/3`:

  - Call the provided function in the caller process
  - Call the provided function exactly once
  - Preserve the function return value
  - Preserve exception/throw/exit semantics

  ### Asynchronous work (Tasks)

      span_ctx = Jido.Observe.start_span([:jido, :agent, :async, :request], %{agent_id: id})

      Task.start(fn ->
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

  Async lifecycle spans remain explicit and context-neutral by default. Process-local
  tracing context is not implicitly attached across process boundaries.

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

  alias Jido.Observe.Config, as: ObserveConfig
  alias Jido.Observe.Log
  alias Jido.Observe.SpanCtx
  alias Jido.Tracing.Context, as: TracingContext

  @type event_prefix :: [atom()]
  @type metadata :: map()
  @type measurements :: map()
  @type span_ctx :: SpanCtx.t()
  @type tracer_failure_mode :: :warn | :strict

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
    enriched_metadata = enrich_with_correlation(metadata)
    tracer_module = tracer(enriched_metadata)

    if function_exported?(tracer_module, :with_span_scope, 3) do
      span_ctx = init_span_ctx(event_prefix, enriched_metadata, tracer_module)
      with_span_scoped(span_ctx, fun)
    else
      with_span_legacy(event_prefix, metadata, fun)
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

      Task.start(fn ->
        result = do_work()
        Jido.Observe.finish_span(span_ctx, %{output_bytes: byte_size(result)})
      end)
  """
  @spec start_span(event_prefix(), metadata()) :: span_ctx()
  def start_span(event_prefix, metadata) when is_list(event_prefix) and is_map(metadata) do
    %SpanCtx{} = span_ctx = init_span_ctx(event_prefix, metadata)

    tracer_ctx =
      invoke_tracer_callback(
        span_ctx,
        :span_start,
        [event_prefix, span_ctx.metadata],
        nil,
        "span_start/2"
      )

    %SpanCtx{span_ctx | tracer_ctx: tracer_ctx}
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
    measurements = emit_stop_event(span_ctx, extra_measurements)

    invoke_tracer_callback(
      span_ctx,
      :span_stop,
      [span_ctx.tracer_ctx, measurements],
      :ok,
      "span_stop/2"
    )

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
    invoke_tracer_callback(
      span_ctx,
      :span_exception,
      [span_ctx.tracer_ctx, kind, reason, stacktrace],
      :ok,
      "span_exception/4",
      fn -> emit_exception_event(span_ctx, kind, reason, stacktrace) end
    )

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
  Emits a telemetry event unconditionally.

  Unlike `emit_debug_event/3`, this helper does not check debug configuration.
  It is intended for domain-level events that should always be emitted.

  Trace correlation metadata from `Jido.Tracing.Context` is merged in automatically
  when present.

  ## Parameters

  - `event_prefix` - Telemetry event name
  - `measurements` - Map of measurements (durations, counts, etc.)
  - `metadata` - Map of metadata (agent_id, iteration, etc.)

  ## Example

      Jido.Observe.emit_event(
        [:jido, :agent, :workflow, :step],
        %{step_duration_ns: 1_234_567},
        %{agent_id: agent.id, step: "plan"}
      )
  """
  @spec emit_event(event_prefix(), measurements(), metadata()) :: :ok
  def emit_event(event_prefix, measurements \\ %{}, metadata \\ %{})

  def emit_event(event_prefix, measurements, metadata)
      when is_list(event_prefix) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(event_prefix, measurements, enrich_with_correlation(metadata))
    :ok
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
    instance = Map.get(metadata, :jido_instance)

    if ObserveConfig.debug_events_enabled?(instance) do
      emit_event(event_prefix, measurements, metadata)
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
    ObserveConfig.debug_events_enabled?(nil)
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
    instance = Keyword.get(opts, :jido_instance)
    should_redact = force_redact || ObserveConfig.redact_sensitive?(instance)

    if should_redact do
      "[REDACTED]"
    else
      value
    end
  end

  defp with_span_legacy(event_prefix, metadata, fun) do
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

  defp with_span_scoped(%SpanCtx{} = span_ctx, fun) do
    key = {__MODULE__, :scoped_guard, make_ref()}
    wrapped_fun = scoped_wrapped_fun(fun, span_ctx, key, self())

    Process.put(key, %{count: 0, outcome: nil})

    try do
      tracer_result =
        invoke_scoped_callback(span_ctx, key, wrapped_fun, fn ->
          apply(span_ctx.tracer_module, :with_span_scope, [
            span_ctx.event_prefix,
            span_ctx.metadata,
            wrapped_fun
          ])
        end)

      resolve_scoped_callback_result(span_ctx, key, tracer_result, wrapped_fun)
    after
      Process.delete(key)
    end
  end

  defp invoke_scoped_callback(%SpanCtx{} = span_ctx, key, wrapped_fun, callback_fun) do
    try do
      callback_fun.()
    rescue
      e ->
        handle_scoped_callback_failure(span_ctx, key, {:error, e, __STACKTRACE__}, wrapped_fun)
    catch
      kind, reason ->
        handle_scoped_callback_failure(span_ctx, key, {kind, reason, __STACKTRACE__}, wrapped_fun)
    end
  end

  defp handle_scoped_callback_failure(%SpanCtx{} = span_ctx, key, failure, wrapped_fun) do
    %{outcome: outcome} = scoped_state(key)

    case outcome do
      {:raised, kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)

      {:ok, result} ->
        case tracer_failure_mode(span_ctx.metadata) do
          :warn ->
            log_tracer_warning(span_ctx, "with_span_scope/3", failure)
            result

          :strict ->
            raise_tracer_failure(span_ctx, "with_span_scope/3", failure)
        end

      nil ->
        case tracer_failure_mode(span_ctx.metadata) do
          :warn ->
            log_tracer_warning(span_ctx, "with_span_scope/3", failure)
            wrapped_fun.()

          :strict ->
            raise_tracer_failure(span_ctx, "with_span_scope/3", failure)
        end
    end
  end

  defp resolve_scoped_callback_result(%SpanCtx{} = span_ctx, key, tracer_result, wrapped_fun) do
    %{count: count, outcome: outcome} = scoped_state(key)

    case outcome do
      nil ->
        handle_scoped_missing_invocation(span_ctx, wrapped_fun)

      {:ok, result} ->
        handle_scoped_success_result(span_ctx, tracer_result, result, count)

      {:raised, kind, reason, stacktrace} ->
        handle_scoped_raised_result(span_ctx, tracer_result, count)
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp handle_scoped_missing_invocation(%SpanCtx{} = span_ctx, wrapped_fun) do
    message = "did not invoke wrapped function"

    case tracer_failure_mode(span_ctx.metadata) do
      :warn ->
        log_scoped_contract_warning(span_ctx, message)
        wrapped_fun.()

      :strict ->
        raise_scoped_contract_violation(span_ctx, message)
    end
  end

  defp handle_scoped_success_result(%SpanCtx{} = span_ctx, tracer_result, result, count) do
    has_violation = false

    has_violation =
      if count > 1 do
        handle_scoped_violation(span_ctx, "invoked wrapped function more than once")
        true
      else
        has_violation
      end

    has_violation =
      if tracer_result !== result do
        handle_scoped_violation(span_ctx, "did not preserve wrapped function return value")
        true
      else
        has_violation
      end

    if has_violation and tracer_failure_mode(span_ctx.metadata) == :strict do
      raise_scoped_contract_violation(
        span_ctx,
        "strict mode rejected scoped callback contract violations"
      )
    end

    result
  end

  defp handle_scoped_raised_result(%SpanCtx{} = span_ctx, _tracer_result, count) do
    if count > 1 do
      log_scoped_contract_warning(span_ctx, "invoked wrapped function more than once")
    end

    log_scoped_contract_warning(span_ctx, "swallowed wrapped function exception")
  end

  defp handle_scoped_violation(%SpanCtx{} = span_ctx, message) do
    case tracer_failure_mode(span_ctx.metadata) do
      :warn ->
        log_scoped_contract_warning(span_ctx, message)

      :strict ->
        :ok
    end
  end

  defp scoped_wrapped_fun(fun, span_ctx, key, owner_pid) do
    fn ->
      if self() != owner_pid do
        raise RuntimeError,
              "with_span_scope/3 must execute wrapped function in caller process " <>
                "(owner=#{inspect(owner_pid)}, caller=#{inspect(self())})"
      else
        state = scoped_state(key)

        case state.count do
          0 ->
            Process.put(key, %{count: 1, outcome: nil})
            execute_scoped_fun(fun, span_ctx, key)

          count when is_integer(count) and count > 0 ->
            Process.put(key, %{state | count: count + 1})
            replay_scoped_outcome(state.outcome)
        end
      end
    end
  end

  defp execute_scoped_fun(fun, span_ctx, key) do
    try do
      result = fun.()
      emit_stop_event(span_ctx)
      Process.put(key, %{count: 1, outcome: {:ok, result}})
      result
    rescue
      e ->
        stacktrace = __STACKTRACE__
        emit_exception_event(span_ctx, :error, e, stacktrace)
        Process.put(key, %{count: 1, outcome: {:raised, :error, e, stacktrace}})
        reraise e, stacktrace
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        emit_exception_event(span_ctx, kind, reason, stacktrace)
        Process.put(key, %{count: 1, outcome: {:raised, kind, reason, stacktrace}})
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp replay_scoped_outcome({:ok, result}), do: result

  defp replay_scoped_outcome({:raised, kind, reason, stacktrace}) do
    :erlang.raise(kind, reason, stacktrace)
  end

  defp replay_scoped_outcome(_), do: nil

  defp scoped_state(key) do
    Process.get(key, %{count: 0, outcome: nil})
  end

  defp init_span_ctx(event_prefix, metadata, tracer_module \\ nil)

  defp init_span_ctx(event_prefix, metadata, nil) do
    enriched_metadata = enrich_with_correlation(metadata)
    tracer_module = tracer(enriched_metadata)
    init_span_ctx(event_prefix, enriched_metadata, tracer_module)
  end

  defp init_span_ctx(event_prefix, metadata, tracer_module)
       when is_list(event_prefix) and is_map(metadata) and is_atom(tracer_module) do
    start_time = System.monotonic_time(:nanosecond)
    start_system_time = System.system_time(:nanosecond)

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: start_system_time},
      metadata
    )

    %SpanCtx{
      event_prefix: event_prefix,
      start_time: start_time,
      start_system_time: start_system_time,
      metadata: metadata,
      tracer_module: tracer_module,
      tracer_ctx: nil
    }
  end

  defp emit_stop_event(%SpanCtx{} = span_ctx, extra_measurements \\ %{}) do
    duration = System.monotonic_time(:nanosecond) - span_ctx.start_time
    measurements = Map.merge(%{duration: duration}, extra_measurements)

    :telemetry.execute(
      span_ctx.event_prefix ++ [:stop],
      measurements,
      span_ctx.metadata
    )

    measurements
  end

  defp emit_exception_event(%SpanCtx{} = span_ctx, kind, reason, stacktrace) do
    duration = System.monotonic_time(:nanosecond) - span_ctx.start_time

    error_metadata =
      Map.merge(span_ctx.metadata, %{
        kind: kind,
        error: reason,
        stacktrace: stacktrace
      })

    :telemetry.execute(
      span_ctx.event_prefix ++ [:exception],
      %{duration: duration},
      error_metadata
    )
  end

  defp invoke_tracer_callback(
         %SpanCtx{} = span_ctx,
         callback,
         args,
         fallback,
         callback_name,
         before_fun \\ nil
       ) do
    if is_function(before_fun, 0) do
      before_fun.()
    end

    try do
      apply(span_ctx.tracer_module || tracer(span_ctx.metadata), callback, args)
    rescue
      e ->
        handle_tracer_failure(span_ctx, callback_name, {:error, e, __STACKTRACE__}, fallback)
    catch
      kind, reason ->
        handle_tracer_failure(span_ctx, callback_name, {kind, reason, __STACKTRACE__}, fallback)
    end
  end

  defp handle_tracer_failure(%SpanCtx{} = span_ctx, callback_name, failure, fallback) do
    case tracer_failure_mode(span_ctx.metadata) do
      :warn ->
        log_tracer_warning(span_ctx, callback_name, failure)
        fallback

      :strict ->
        raise_tracer_failure(span_ctx, callback_name, failure)
    end
  end

  defp log_tracer_warning(%SpanCtx{} = span_ctx, callback_name, failure) do
    Logger.warning(
      "Jido.Observe tracer #{callback_name} failed " <>
        "(tracer=#{inspect(span_ctx.tracer_module || tracer(span_ctx.metadata))}, " <>
        "event_prefix=#{inspect(span_ctx.event_prefix)}, " <>
        "failure_mode=#{tracer_failure_mode(span_ctx.metadata)}): #{format_tracer_failure(failure)}"
    )
  end

  defp log_scoped_contract_warning(%SpanCtx{} = span_ctx, message) do
    Logger.warning(
      "Jido.Observe tracer with_span_scope/3 contract violation " <>
        "(tracer=#{inspect(span_ctx.tracer_module)}, " <>
        "event_prefix=#{inspect(span_ctx.event_prefix)}, " <>
        "failure_mode=#{tracer_failure_mode(span_ctx.metadata)}): #{message}"
    )
  end

  defp raise_tracer_failure(%SpanCtx{} = span_ctx, callback_name, failure) do
    raise RuntimeError,
          "Jido.Observe tracer #{callback_name} failed " <>
            "(tracer=#{inspect(span_ctx.tracer_module || tracer(span_ctx.metadata))}, " <>
            "event_prefix=#{inspect(span_ctx.event_prefix)}, " <>
            "failure_mode=#{tracer_failure_mode(span_ctx.metadata)}): #{format_tracer_failure(failure)}"
  end

  defp raise_scoped_contract_violation(%SpanCtx{} = span_ctx, message) do
    raise RuntimeError,
          "Jido.Observe tracer with_span_scope/3 contract violation " <>
            "(tracer=#{inspect(span_ctx.tracer_module)}, " <>
            "event_prefix=#{inspect(span_ctx.event_prefix)}, " <>
            "failure_mode=#{tracer_failure_mode(span_ctx.metadata)}): #{message}"
  end

  defp format_tracer_failure({:error, error, _stacktrace}), do: inspect(error)
  defp format_tracer_failure({kind, reason, _stacktrace}), do: inspect({kind, reason})

  defp tracer(metadata) when is_map(metadata) do
    instance = Map.get(metadata, :jido_instance)
    ObserveConfig.tracer(instance)
  end

  defp tracer_failure_mode(metadata) when is_map(metadata) do
    instance = Map.get(metadata, :jido_instance)
    ObserveConfig.tracer_failure_mode(instance)
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
