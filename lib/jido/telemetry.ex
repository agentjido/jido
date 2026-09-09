defmodule Jido.Telemetry do
  @moduledoc """
  Semantic logging and metrics for the Jido runtime.

  Jido emits version-1 semantic events for Agent lifecycle, Turn result,
  commit, Directive work, Turn settlement, admission rejection, persistence,
  and static local Topology operations. Spans use `:start`, `:stop`, and
  `:exception`. Returned errors use `:stop`; faults that escape the observed
  boundary use `:exception`.

  A successful Turn span ends when its commit becomes live.
  `[:jido, :agent, :turn, :settled]` is a separate later fact after Directive
  work. Agent lifecycle operations are `:activate`, `:stop`, `:hibernate`, and
  `:thaw`. Persistence operations are `:load`, `:compare_and_swap`, and
  `:delete`. Local Topology operations are `:activate`, `:repair`, and
  `:cleanup`.

  Semantic metadata is a strict scalar allowlist. It includes schema version,
  bounded identity and correlation, public status, and registered error codes.
  Revisions, durations, and counts are measurements. Events exclude state,
  payloads, records, raw errors, process handles, and caller context.

  `metrics/0` returns low-cardinality semantic metrics. `legacy_metrics/0`
  keeps the old Agent Server metric definitions. The old events, log handler,
  `Jido.Observe`, tracing, and debug history also remain for compatibility.

  Handlers run in the emitting process and must return quickly. A host exporter
  or OpenTelemetry bridge must copy bounded events to its own process. Jido
  does not start an SDK or exporter. Abrupt process or VM loss can prevent
  final events, so this stream is not a durable journal.
  """

  require Logger

  alias Jido.Observe.Config, as: ObserveConfig
  alias Jido.Telemetry.Formatter
  alias Jido.Telemetry.Semantic

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
  @semantic_handler_id "jido-semantic-logger"

  @doc """
  Attaches telemetry handlers. Idempotent — safe to call multiple times.
  Called from application startup.
  """
  @spec setup() :: :ok
  def setup do
    attach(@handler_id, legacy_events(), &__MODULE__.handle_event/4)
    attach(@semantic_handler_id, semantic_terminal_events(), &__MODULE__.handle_semantic_event/4)
    :ok
  end

  @doc """
  Returns low-cardinality metric definitions for the semantic event catalog.

  Wire these into your reporter in your application:

      TelemetryMetricsPrometheus.init(Jido.Telemetry.metrics())
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      Telemetry.Metrics.counter("jido.agent.lifecycle.stop.count",
        event_name: [:jido, :agent, :lifecycle, :stop],
        tags: [:operation, :status]
      ),
      Telemetry.Metrics.summary("jido.agent.lifecycle.stop.duration",
        event_name: [:jido, :agent, :lifecycle, :stop],
        tags: [:operation, :status],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.agent.turn.stop.count",
        event_name: [:jido, :agent, :turn, :stop],
        tags: [:status, :stage]
      ),
      Telemetry.Metrics.summary("jido.agent.turn.stop.duration",
        event_name: [:jido, :agent, :turn, :stop],
        tags: [:status, :stage],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.agent.turn.settled.count",
        event_name: [:jido, :agent, :turn, :settled],
        tags: [:status, :stage]
      ),
      Telemetry.Metrics.summary("jido.agent.turn.settled.duration",
        event_name: [:jido, :agent, :turn, :settled],
        tags: [:status, :stage],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.agent.commit.stop.count",
        event_name: [:jido, :agent, :commit, :stop],
        tags: [:status]
      ),
      Telemetry.Metrics.summary("jido.agent.commit.stop.duration",
        event_name: [:jido, :agent, :commit, :stop],
        tags: [:status],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.agent.directive.stop.count",
        event_name: [:jido, :agent, :directive, :stop],
        tags: [:status]
      ),
      Telemetry.Metrics.summary("jido.agent.directive.stop.duration",
        event_name: [:jido, :agent, :directive, :stop],
        tags: [:status],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.agent.admission.rejected.count",
        event_name: [:jido, :agent, :admission, :rejected],
        tags: [:admission_reason]
      ),
      Telemetry.Metrics.counter("jido.persistence.operation.stop.count",
        event_name: [:jido, :persistence, :operation, :stop],
        tags: [:operation, :status, :persistence_reason]
      ),
      Telemetry.Metrics.summary("jido.persistence.operation.stop.duration",
        event_name: [:jido, :persistence, :operation, :stop],
        tags: [:operation, :status, :persistence_reason],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.topology.operation.stop.count",
        event_name: [:jido, :topology, :operation, :stop],
        tags: [:topology_operation, :status]
      ),
      Telemetry.Metrics.summary("jido.topology.operation.stop.duration",
        event_name: [:jido, :topology, :operation, :stop],
        tags: [:topology_operation, :status],
        unit: {:native, :millisecond}
      )
    ]
  end

  @doc "Returns the retained Agent Server metric definitions."
  @spec legacy_metrics() :: [Telemetry.Metrics.t()]
  def legacy_metrics do
    [
      Telemetry.Metrics.counter("jido.agent_server.signal.stop.count",
        event_name: [:jido, :agent_server, :signal, :stop],
        tags: [:jido_instance, :signal_type],
        tag_values: &instance_tag_values/1,
        description: "Total Agent Signals processed"
      ),
      Telemetry.Metrics.summary("jido.agent_server.signal.stop.duration",
        event_name: [:jido, :agent_server, :signal, :stop],
        tags: [:jido_instance, :signal_type],
        tag_values: &instance_tag_values/1,
        unit: {:native, :millisecond},
        description: "Agent Signal duration summary"
      ),
      Telemetry.Metrics.counter("jido.agent_server.directive.stop.count",
        event_name: [:jido, :agent_server, :directive, :stop],
        tags: [:jido_instance, :directive_type],
        tag_values: &instance_tag_values/1,
        description: "Total Agent Directives executed"
      )
    ]
  end

  defp instance_tag_values(meta), do: meta |> Map.new() |> Map.put_new(:jido_instance, :global)

  defp legacy_events do
    [
      [:jido, :agent_server, :signal, :start],
      [:jido, :agent_server, :signal, :stop],
      [:jido, :agent_server, :signal, :exception],
      [:jido, :agent_server, :directive, :start],
      [:jido, :agent_server, :directive, :stop],
      [:jido, :agent_server, :directive, :exception]
    ]
  end

  defp semantic_terminal_events do
    spans =
      for prefix <- [
            [:jido, :agent, :lifecycle],
            [:jido, :agent, :turn],
            [:jido, :agent, :commit],
            [:jido, :agent, :directive],
            [:jido, :persistence, :operation],
            [:jido, :topology, :operation]
          ],
          ending <- [:stop, :exception],
          do: prefix ++ [ending]

    spans ++
      [
        [:jido, :agent, :turn, :settled],
        [:jido, :agent, :admission, :rejected]
      ]
  end

  defp attach(id, events, handler) do
    case :telemetry.attach_many(id, events, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle_semantic_event(event, measurements, metadata, _config) do
    mode = semantic_log_mode()
    metadata = Semantic.normalize_metadata(metadata)
    measurements = Semantic.normalize_measurements(measurements)

    if log_semantic?(mode, event, measurements, metadata) do
      message =
        "[jido.semantic] event=#{event |> Enum.drop(1) |> Enum.join(".")} " <>
          Formatter.format_metadata(Map.merge(metadata, measurements), max_value_length: 128)

      if semantic_error?(event, metadata),
        do: Logger.warning(message),
        else: Logger.debug(message)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp semantic_log_mode do
    config = Application.get_env(:jido, :telemetry, [])
    explicit = config_value(config, :semantic_log_mode)

    cond do
      explicit in [:off, :errors, :interesting, :all] -> explicit
      config_value(config, :log_level) == :trace -> :all
      config_value(config, :log_level) == :debug -> :interesting
      true -> :off
    end
  end

  defp log_semantic?(:off, _event, _measurements, _metadata), do: false
  defp log_semantic?(:all, _event, _measurements, _metadata), do: true

  defp log_semantic?(:errors, event, _measurements, metadata),
    do: semantic_error?(event, metadata)

  defp log_semantic?(:interesting, event, measurements, metadata) do
    semantic_error?(event, metadata) or slow_semantic?(measurements)
  end

  defp semantic_error?(event, metadata) do
    List.last(event) == :exception or Map.get(metadata, :status) not in [nil, :ok]
  end

  defp slow_semantic?(measurements) do
    duration = Map.get(measurements, :duration, 0)
    threshold = semantic_slow_threshold_ms()
    Formatter.to_ms(duration) >= threshold
  end

  defp semantic_slow_threshold_ms do
    config = Application.get_env(:jido, :telemetry, [])

    case config_value(config, :semantic_slow_threshold_ms) do
      value when is_integer(value) and value >= 0 -> value
      _value -> 1_000
    end
  end

  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil

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
