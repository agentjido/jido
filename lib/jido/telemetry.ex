defmodule Jido.Telemetry do
  @moduledoc """
  Production-ready telemetry for Jido Agent operations.

  Provides structured, scannable logging with intelligent filtering to reduce noise
  while preserving actionable debugging information.

  ## Log Levels

  The telemetry system uses three effective log levels:

  - **INFO** - Developer narrative for user-facing interactions (request start/stop)
  - **DEBUG** - Interesting events only (slow operations, signals with directives, errors)
  - **TRACE** - Fine-grained internal churn (every signal/directive) - opt-in via config

  ## Configuration

  Configure via application environment:

      config :jido, :telemetry,
        log_level: :debug,                    # :trace | :debug | :info
        slow_signal_threshold_ms: 10,         # Log signals slower than this
        slow_directive_threshold_ms: 5,       # Log directives slower than this
        interesting_signal_types: [           # Always log these signal types
          "jido.agent.user_request",
          "jido.tool.result",
          "jido.llm.done"
        ],
        log_prompts: false,                   # Privacy: don't log LLM prompts
        log_tool_args: :keys_only             # :keys_only | :full | :none

  ## "Interestingness" Filtering

  At DEBUG level, signals are only logged if they are "interesting":
  - Duration exceeds `slow_signal_threshold_ms`
  - Produced one or more directives
  - Signal type is in `interesting_signal_types`
  - An error occurred

  This reduces log spam from high-frequency internal signals while preserving
  visibility into operations that matter.

  ## Structured Output

  All log entries include structured metadata for filtering and correlation:
  - `trace_id`, `span_id` - For distributed tracing
  - `agent_id`, `agent_module` - Agent identification
  - `signal_type`, `directive_count`, `directive_types` - What happened
  - `duration` - Formatted timing (e.g., "12.3ms")

  ## Events

  ### Agent Events
  - `[:jido, :agent, :cmd, :start]` - Agent command execution started
  - `[:jido, :agent, :cmd, :stop]` - Agent command execution completed
  - `[:jido, :agent, :cmd, :exception]` - Agent command execution failed

  ### AgentServer Events
  - `[:jido, :agent_server, :signal, :start]` - Signal processing started
  - `[:jido, :agent_server, :signal, :stop]` - Signal processing completed
  - `[:jido, :agent_server, :signal, :exception]` - Signal processing failed
  - `[:jido, :agent_server, :directive, :start]` - Directive execution started
  - `[:jido, :agent_server, :directive, :stop]` - Directive execution completed
  - `[:jido, :agent_server, :directive, :exception]` - Directive execution failed
  - `[:jido, :agent_server, :queue, :overflow]` - Directive queue overflow

  ### Strategy Events
  - `[:jido, :agent, :strategy, :init, :start]` - Strategy initialization started
  - `[:jido, :agent, :strategy, :init, :stop]` - Strategy initialization completed
  - `[:jido, :agent, :strategy, :init, :exception]` - Strategy initialization failed
  - `[:jido, :agent, :strategy, :cmd, :start]` - Strategy command execution started
  - `[:jido, :agent, :strategy, :cmd, :stop]` - Strategy command execution completed
  - `[:jido, :agent, :strategy, :cmd, :exception]` - Strategy command execution failed
  - `[:jido, :agent, :strategy, :tick, :start]` - Strategy tick started
  - `[:jido, :agent, :strategy, :tick, :stop]` - Strategy tick completed
  - `[:jido, :agent, :strategy, :tick, :exception]` - Strategy tick failed
  """

  require Logger

  alias Jido.Observe.Config, as: ObserveConfig
  alias Jido.Telemetry.Formatter

  @typedoc """
  Supported telemetry event names.
  """
  @type event_name :: [atom(), ...]

  @typedoc """
  Telemetry measurements map.
  """
  @type measurements :: %{
          optional(:system_time) => integer(),
          optional(:duration) => integer(),
          atom() => term()
        }

  @typedoc """
  Telemetry metadata map.
  """
  @type metadata :: %{
          optional(:agent_id) => String.t(),
          optional(:agent_module) => module(),
          optional(:strategy) => module(),
          optional(:action) => term(),
          optional(:directive_count) => non_neg_integer(),
          optional(:error) => term(),
          atom() => term()
        }

  @handler_id "jido-agent-metrics"

  @doc """
  Attaches telemetry handlers. Idempotent — safe to call multiple times.
  Called from application startup.
  """
  @spec setup() :: :ok
  def setup do
    _ = :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, events(), &__MODULE__.handle_event/4, nil)
    :ok
  end

  @doc """
  Returns telemetry metric definitions with automatic per-instance scoping.

  Wire these into your reporter in your application:

      TelemetryMetricsPrometheus.init(Jido.Telemetry.metrics())
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    tag_values = &instance_tag_values/1

    [
      Telemetry.Metrics.counter("jido.agent.cmd.stop.count",
        event_name: [:jido, :agent, :cmd, :stop],
        tags: [:jido_instance],
        tag_values: tag_values,
        description: "Total number of agent commands executed"
      ),
      Telemetry.Metrics.summary("jido.agent.cmd.stop.duration",
        tags: [:jido_instance],
        tag_values: tag_values,
        unit: {:native, :millisecond},
        description: "Agent command duration summary"
      ),
      Telemetry.Metrics.counter("jido.agent_server.signal.stop.count",
        event_name: [:jido, :agent_server, :signal, :stop],
        tags: [:jido_instance, :signal_type],
        tag_values: tag_values,
        description: "Total signals processed"
      ),
      Telemetry.Metrics.summary("jido.agent_server.signal.stop.duration",
        tags: [:jido_instance, :signal_type],
        tag_values: tag_values,
        unit: {:native, :millisecond},
        description: "Signal processing duration summary"
      ),
      Telemetry.Metrics.counter("jido.agent_server.directive.stop.count",
        event_name: [:jido, :agent_server, :directive, :stop],
        tags: [:jido_instance, :directive_type],
        tag_values: tag_values,
        description: "Total directives executed"
      ),
      Telemetry.Metrics.counter("jido.agent_server.queue.overflow.count",
        event_name: [:jido, :agent_server, :queue, :overflow],
        tags: [:jido_instance],
        tag_values: tag_values,
        description: "Queue overflow count"
      )
    ]
  end

  defp instance_tag_values(meta) do
    meta
    |> Map.new()
    |> Map.put_new(:jido_instance, :global)
  end

  defp events do
    [
      [:jido, :agent, :cmd, :start],
      [:jido, :agent, :cmd, :stop],
      [:jido, :agent, :cmd, :exception],
      [:jido, :agent, :strategy, :init, :start],
      [:jido, :agent, :strategy, :init, :stop],
      [:jido, :agent, :strategy, :init, :exception],
      [:jido, :agent, :strategy, :cmd, :start],
      [:jido, :agent, :strategy, :cmd, :stop],
      [:jido, :agent, :strategy, :cmd, :exception],
      [:jido, :agent, :strategy, :tick, :start],
      [:jido, :agent, :strategy, :tick, :stop],
      [:jido, :agent, :strategy, :tick, :exception],
      [:jido, :agent_server, :signal, :start],
      [:jido, :agent_server, :signal, :stop],
      [:jido, :agent_server, :signal, :exception],
      [:jido, :agent_server, :directive, :start],
      [:jido, :agent_server, :directive, :stop],
      [:jido, :agent_server, :directive, :exception],
      [:jido, :agent_server, :queue, :overflow]
    ]
  end

  @doc """
  Handles telemetry events for agent and strategy operations.

  Uses intelligent filtering to reduce noise while preserving actionable information.
  Events are logged based on "interestingness" criteria configured via `Jido.Telemetry.Config`.
  """
  @spec handle_event(event_name(), measurements(), metadata(), config :: term()) :: :ok

  # ---------------------------------------------------------------------------
  # Agent Command Events
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent, :cmd, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent, :cmd, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)
    duration_ms = Formatter.to_ms(duration)
    directive_count = metadata[:directive_count] || 0

    if interesting_agent_cmd?(instance, duration_ms, directive_count, metadata) do
      Logger.debug(
        fn ->
          "[agent.cmd] #{format_module(metadata[:agent_module])} " <>
            "action=#{Formatter.format_action(metadata[:action])} " <>
            "directives=#{directive_count} " <>
            "duration=#{Formatter.format_duration(duration)}"
        end,
        agent_id: metadata[:agent_id],
        trace_id: metadata[:jido_trace_id],
        span_id: metadata[:jido_span_id]
      )
    end

    :ok
  end

  def handle_event([:jido, :agent, :cmd, :exception], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0)

    Logger.warning(
      "[agent.cmd.error] #{format_module(metadata[:agent_module])} " <>
        "action=#{Formatter.format_action(metadata[:action])} " <>
        "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
        "duration=#{Formatter.format_duration(duration)}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  # ---------------------------------------------------------------------------
  # Strategy Events
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent, :strategy, :init, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent, :strategy, :init, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)

    if ObserveConfig.trace_enabled?(instance) do
      Logger.debug(
        fn ->
          "[strategy.init] #{format_module(metadata[:strategy])} " <>
            "duration=#{Formatter.format_duration(duration)}"
        end,
        agent_id: metadata[:agent_id],
        trace_id: metadata[:jido_trace_id]
      )
    end

    :ok
  end

  def handle_event(
        [:jido, :agent, :strategy, :init, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0)

    Logger.warning(
      "[strategy.init.error] #{format_module(metadata[:strategy])} " <>
        "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
        "duration=#{Formatter.format_duration(duration)}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  def handle_event([:jido, :agent, :strategy, :cmd, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent, :strategy, :cmd, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)
    duration_ms = Formatter.to_ms(duration)
    directive_count = metadata[:directive_count] || 0

    if interesting_strategy_cmd?(instance, duration_ms, directive_count) do
      Logger.debug(
        fn ->
          "[strategy.cmd] #{format_module(metadata[:strategy])} " <>
            "directives=#{directive_count} " <>
            "duration=#{Formatter.format_duration(duration)}"
        end,
        agent_id: metadata[:agent_id],
        trace_id: metadata[:jido_trace_id]
      )
    end

    :ok
  end

  def handle_event(
        [:jido, :agent, :strategy, :cmd, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0)

    Logger.warning(
      "[strategy.cmd.error] #{format_module(metadata[:strategy])} " <>
        "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
        "duration=#{Formatter.format_duration(duration)}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  def handle_event([:jido, :agent, :strategy, :tick, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent, :strategy, :tick, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)
    duration_ms = Formatter.to_ms(duration)

    # Only log slow ticks - ticks are high frequency
    if duration_ms > ObserveConfig.slow_signal_threshold_ms(instance) do
      Logger.debug(
        fn ->
          "[strategy.tick] #{format_module(metadata[:strategy])} " <>
            "duration=#{Formatter.format_duration(duration)} (slow)"
        end,
        agent_id: metadata[:agent_id],
        trace_id: metadata[:jido_trace_id]
      )
    end

    :ok
  end

  def handle_event(
        [:jido, :agent, :strategy, :tick, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0)

    Logger.warning(
      "[strategy.tick.error] #{format_module(metadata[:strategy])} " <>
        "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
        "duration=#{Formatter.format_duration(duration)}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  # ---------------------------------------------------------------------------
  # AgentServer Signal Events - The main source of log noise
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent_server, :signal, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent_server, :signal, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)
    duration_ms = Formatter.to_ms(duration)
    directive_count = metadata[:directive_count] || 0
    signal_type = metadata[:signal_type]

    cond do
      # At trace level, log everything
      ObserveConfig.trace_enabled?(instance) ->
        log_signal_stop(metadata, duration, directive_count)

      # At debug level, only log "interesting" signals
      ObserveConfig.debug_enabled?(instance) and
          interesting_signal?(instance, signal_type, duration_ms, directive_count, metadata) ->
        log_signal_stop(metadata, duration, directive_count)

      # Otherwise, stay silent
      true ->
        :ok
    end

    :ok
  end

  def handle_event(
        [:jido, :agent_server, :signal, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0)

    Logger.warning(
      "[signal.error] type=#{Formatter.format_signal_type(metadata[:signal_type])} " <>
        "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
        "duration=#{Formatter.format_duration(duration)}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  # ---------------------------------------------------------------------------
  # AgentServer Directive Events
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent_server, :directive, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent_server, :directive, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)
    duration_ms = Formatter.to_ms(duration)
    directive_type = metadata[:directive_type]

    cond do
      # At trace level, log everything
      ObserveConfig.trace_enabled?(instance) ->
        log_directive_stop(metadata, duration)

      # At debug level, only log slow or interesting directives
      ObserveConfig.debug_enabled?(instance) and
          interesting_directive?(instance, directive_type, duration_ms, metadata) ->
        log_directive_stop(metadata, duration)

      # Otherwise, stay silent
      true ->
        :ok
    end

    :ok
  end

  def handle_event(
        [:jido, :agent_server, :directive, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0)

    Logger.warning(
      "[directive.error] type=#{metadata[:directive_type]} " <>
        "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
        "duration=#{Formatter.format_duration(duration)}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  def handle_event([:jido, :agent_server, :queue, :overflow], measurements, metadata, _config) do
    Logger.warning(
      "[queue.overflow] signal_type=#{Formatter.format_signal_type(metadata[:signal_type])} " <>
        "queue_size=#{measurements[:queue_size]}",
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id]
    )
  end

  # ---------------------------------------------------------------------------
  # Private: Logging Helpers
  # ---------------------------------------------------------------------------

  defp log_signal_stop(metadata, duration, directive_count) do
    Logger.debug(
      fn ->
        "[signal] type=#{Formatter.format_signal_type(metadata[:signal_type])} " <>
          "directives=#{directive_count} " <>
          "duration=#{Formatter.format_duration(duration)}"
      end,
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id]
    )
  end

  defp log_directive_stop(metadata, duration) do
    Logger.debug(
      fn ->
        "[directive] type=#{metadata[:directive_type]} " <>
          "result=#{metadata[:result]} " <>
          "duration=#{Formatter.format_duration(duration)}"
      end,
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id]
    )
  end

  # ---------------------------------------------------------------------------
  # Private: Interestingness Checks
  # ---------------------------------------------------------------------------

  defp interesting_signal?(instance, signal_type, duration_ms, directive_count, metadata) do
    is_slow = duration_ms > ObserveConfig.slow_signal_threshold_ms(instance)
    has_directives = directive_count > 0
    is_interesting_type = ObserveConfig.interesting_signal_type?(instance, to_string(signal_type))
    has_error = metadata[:error] != nil

    is_slow or has_directives or is_interesting_type or has_error
  end

  defp interesting_directive?(instance, directive_type, duration_ms, metadata) do
    is_slow = duration_ms > ObserveConfig.slow_directive_threshold_ms(instance)
    has_error = metadata[:error] != nil
    interesting_types = ["Tool", "LLM", "Await", "Spawn"]
    is_interesting_type = directive_type in interesting_types

    is_slow or has_error or is_interesting_type
  end

  defp interesting_agent_cmd?(instance, duration_ms, directive_count, metadata) do
    is_slow = duration_ms > ObserveConfig.slow_signal_threshold_ms(instance)
    has_directives = directive_count > 0
    has_error = metadata[:error] != nil

    is_slow or has_directives or has_error
  end

  defp interesting_strategy_cmd?(instance, duration_ms, directive_count) do
    is_slow = duration_ms > ObserveConfig.slow_signal_threshold_ms(instance)
    has_directives = directive_count > 0

    is_slow or has_directives
  end

  defp format_module(nil), do: "unknown"

  defp format_module(module) when is_atom(module) do
    case to_string(module) do
      "Elixir." <> rest -> rest
      other -> other
    end
  end

  defp format_module(other), do: Formatter.safe_inspect(other, 50)

  @deprecated "Use Jido.Observe.with_span/3 instead"
  @doc """
  Executes an agent command while emitting telemetry events.

  ## Examples

      Jido.Telemetry.span_agent_cmd(agent, action, fn ->
        # Execute command logic
        {updated_agent, directives}
      end)
  """
  @spec span_agent_cmd(Jido.Agent.t(), term(), (-> result)) :: result when result: term()
  def span_agent_cmd(agent, action, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    metadata = %{
      agent_id: agent.id,
      agent_module: agent.name,
      action: action,
      jido_instance: nil
    }

    :telemetry.execute(
      [:jido, :agent, :cmd, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      {updated_agent, directives} = func.()

      :telemetry.execute(
        [:jido, :agent, :cmd, :stop],
        %{
          duration: System.monotonic_time() - start_time,
          directive_count: length(directives)
        },
        Map.merge(metadata, %{directive_count: length(directives)})
      )

      {updated_agent, directives}
    catch
      kind, reason ->
        stack = __STACKTRACE__

        :telemetry.execute(
          [:jido, :agent, :cmd, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason, stacktrace: stack})
        )

        :erlang.raise(kind, reason, stack)
    end
  end

  @deprecated "Use Jido.Observe.with_span/3 instead"
  @doc """
  Executes a strategy operation while emitting telemetry events.

  ## Examples

      Jido.Telemetry.span_strategy(agent, :init, strategy_module, fn ->
        # Execute strategy logic
        {updated_agent, directives}
      end)
  """
  @spec span_strategy(Jido.Agent.t(), :init | :cmd | :tick, module(), (-> result)) :: result
        when result: term()
  def span_strategy(agent, operation, strategy_module, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    metadata = %{
      agent_id: agent.id,
      strategy: strategy_module,
      jido_instance: nil
    }

    :telemetry.execute(
      [:jido, :agent, :strategy, operation, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = func.()

      measurements = %{duration: System.monotonic_time() - start_time}

      final_metadata =
        case result do
          {_agent, directives} when is_list(directives) ->
            Map.merge(metadata, %{directive_count: length(directives)})

          _ ->
            metadata
        end

      :telemetry.execute(
        [:jido, :agent, :strategy, operation, :stop],
        measurements,
        final_metadata
      )

      result
    catch
      kind, reason ->
        stack = __STACKTRACE__

        :telemetry.execute(
          [:jido, :agent, :strategy, operation, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason, stacktrace: stack})
        )

        :erlang.raise(kind, reason, stack)
    end
  end
end
