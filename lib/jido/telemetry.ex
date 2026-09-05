defmodule Jido.Telemetry do
  @moduledoc """
  Logging and metrics for Jido Agent Server events.

  Agent Servers emit bounded telemetry metadata for Signal execution and
  Directive dispatch. Logging uses the shared observability configuration.

  ## Semantic Agent events

  Live Servers also emit `[:jido, :agent, boundary, event]`, where `boundary`
  is `:lifecycle`, `:turn`, `:commit`, or `:directive`, and `event` is `:start`,
  `:stop`, or `:exception`. Durations and timestamps use native time units.
  Returned errors use `:stop` with status metadata. Escaping faults use
  `:exception`. Action packages can report their own execution exceptions.

  `[:jido, :agent, :turn, :settled]` reports one terminal Outcome after
  Directive completion or failure. A successful Turn span ends at commit;
  settlement can fail after that commit. Metadata contains bounded Agent,
  activation, Signal, Turn, and trace IDs, status, stage, and `committed?`.
  Revisions and Directive counts are measurements. State, payloads, raw error
  details, process handles, and caller context are excluded from these events.

  Lifecycle operations are `:activate` and `:stop`. Each activation, including
  an OTP restart, gets a fresh `activation_id`. Startup spans end when Plugins
  are ready. Stop spans cover cleanup. Abrupt process or VM loss can prevent
  final events; this stream is not a durable event journal.

  The existing `:agent_server` spans remain available for compatibility.
  Handlers run in the emitting process and must return quickly. Exporters
  should copy these bounded events to their own process.
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

  @typedoc "Telemetry metadata map."
  @type metadata :: %{
          optional(:agent_id) => String.t(),
          optional(:agent_module) => module(),
          optional(:signal_type) => String.t(),
          optional(:directive_type) => String.t(),
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
      Telemetry.Metrics.counter("jido.agent_server.signal.stop.count",
        event_name: [:jido, :agent_server, :signal, :stop],
        tags: [:jido_instance, :signal_type],
        tag_values: tag_values,
        description: "Total Agent Signals processed"
      ),
      Telemetry.Metrics.summary("jido.agent_server.signal.stop.duration",
        event_name: [:jido, :agent_server, :signal, :stop],
        tags: [:jido_instance, :signal_type],
        tag_values: tag_values,
        unit: {:native, :millisecond},
        description: "Agent Signal duration summary"
      ),
      Telemetry.Metrics.counter("jido.agent_server.directive.stop.count",
        event_name: [:jido, :agent_server, :directive, :stop],
        tags: [:jido_instance, :directive_type],
        tag_values: tag_values,
        description: "Total Agent Directives executed"
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
      [:jido, :agent_server, :signal, :start],
      [:jido, :agent_server, :signal, :stop],
      [:jido, :agent_server, :signal, :exception],
      [:jido, :agent_server, :directive, :start],
      [:jido, :agent_server, :directive, :stop],
      [:jido, :agent_server, :directive, :exception]
    ]
  end

  @doc """
  Handles Agent Server telemetry events.

  Uses intelligent filtering to reduce noise while preserving actionable information.
  Events are logged based on "interestingness" criteria configured via
  `Jido.Observe.Config`.
  """
  @spec handle_event(event_name(), measurements(), metadata(), config :: term()) :: :ok

  # ---------------------------------------------------------------------------
  # Agent Server Signal Events
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent_server, :signal, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent_server, :signal, :stop], measurements, metadata, _config) do
    instance = metadata[:jido_instance]
    duration = Map.get(measurements, :duration, 0)
    duration_ms = Formatter.to_ms(duration)
    directive_count = metadata[:directive_count] || measurements[:directive_count] || 0
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
      fn ->
        "[signal.error] type=#{Formatter.format_signal_type(metadata[:signal_type])} " <>
          "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
          "duration=#{Formatter.format_duration(duration)}"
      end,
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  # ---------------------------------------------------------------------------
  # Agent Server Directive Events
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent_server, :directive, :start], _measurements, _metadata, _config) do
    :ok
  end

  def handle_event([:jido, :agent_server, :directive, :stop], measurements, metadata, _config) do
    metadata = Map.merge(metadata, Map.take(measurements, [:result]))
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
      fn ->
        "[directive.error] type=#{metadata[:directive_type]} " <>
          "error=#{Formatter.safe_inspect(metadata[:error], 200)} " <>
          "duration=#{Formatter.format_duration(duration)}"
      end,
      agent_id: metadata[:agent_id],
      trace_id: metadata[:jido_trace_id],
      span_id: metadata[:jido_span_id],
      stacktrace: metadata[:stacktrace]
    )
  end

  # ---------------------------------------------------------------------------
  # Private: Logging Helpers
  # ---------------------------------------------------------------------------

  defp log_signal_stop(metadata, duration, directive_count) do
    Logger.debug(
      fn ->
        directive_types =
          metadata[:directive_types]
          |> Formatter.format_directive_types()

        directive_summary =
          if directive_types == "" do
            ""
          else
            "#{directive_types} "
          end

        "[signal] type=#{Formatter.format_signal_type(metadata[:signal_type])} " <>
          "directives=#{directive_count} " <>
          directive_summary <>
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
end
