defmodule Jido.Telemetry do
  @moduledoc """
  The public runtime observability API.

  Jido uses one version-1 semantic event catalog for Telemetry handlers,
  metrics, semantic logs, and optional OpenTelemetry spans. The catalog covers
  Agent lifecycle, Turn result, commit, Plugin commit notification, Directive
  work, Turn settlement, admission rejection, persistence, local Topology
  operations, Topology ownership settlement, and Scheduler delivery.

  A successful Turn span ends when its commit becomes live. Plugin
  notifications and Directive work can continue after this point. The separate
  `[:jido, :agent, :turn, :settled]` event reports the terminal bounded result
  after all owned notification and Directive attempts stop. A post-commit
  failure does not undo the committed Agent or its revision.

  Span events use `:start` and one terminal event. A returned result uses
  `:stop`. An error, throw, or exit that escapes the observed boundary uses
  `:exception`.

  Event metadata has a strict scalar allowlist. It excludes Agent and Plugin
  state, Signal and Directive data, raw errors, records, process handles,
  credentials, and caller context. Durations, revisions, queue sizes, and
  counts are measurements.

  `metrics/0` returns low-cardinality metric definitions. If the optional
  `opentelemetry_api` dependency and a host-managed SDK are active, Jido maps
  the same operations to spans. Jido does not start an SDK or configure
  sampling and export.

  Observation is best effort. It cannot change an Agent result and it is not a
  durable audit record.

  See [Observe Agent Turns](observe-agent-turns.html) and
  [Telemetry, Tracing, and Logs](telemetry-tracing-and-logs.html) for the
  complete event and integration contracts.
  """

  require Logger

  alias Jido.Debug
  alias Jido.Telemetry.{OpenTelemetry, Semantic}

  @semantic_handler_id "jido-semantic-logger"
  @log_scope_key {:jido, :semantic_log_scope}

  @span_metrics [
    {"jido.agent.lifecycle", [:jido, :agent, :lifecycle], [:operation, :status]},
    {"jido.agent.turn", [:jido, :agent, :turn], [:status, :stage]},
    {"jido.agent.commit", [:jido, :agent, :commit], [:status]},
    {"jido.agent.after_commit", [:jido, :agent, :after_commit], [:status]},
    {"jido.agent.directive", [:jido, :agent, :directive], [:status]},
    {"jido.persistence.operation", [:jido, :persistence, :operation],
     [:operation, :status, :persistence_reason]},
    {"jido.topology.operation", [:jido, :topology, :operation], [:topology_operation, :status]}
  ]

  @typedoc "A Jido telemetry event name."
  @type event_name :: [atom(), ...]

  @typedoc "A Jido telemetry measurement map."
  @type measurements :: %{optional(atom()) => integer()}

  @typedoc "A Jido telemetry metadata map."
  @type metadata :: %{atom() => term()}

  @doc """
  Returns metric definitions for the Jido semantic event catalog.

  The result contains count and duration metrics for normal and exception span
  endings. It also contains Turn settlement, admission rejection, Topology
  ownership settlement, and Scheduler delivery metrics. Default tags use only bounded result and
  operation values. They do not use Agent, Signal, Turn, trace, module, or
  error IDs.

  Pass the returned list to a `Telemetry.Metrics` compatible reporter in the
  host application.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    Enum.flat_map(@span_metrics, &span_metrics/1) ++
      [
        Telemetry.Metrics.counter("jido.agent.turn.settled.count",
          event_name: [:jido, :agent, :turn, :settled],
          tags: [:status, :stage]
        ),
        Telemetry.Metrics.summary("jido.agent.turn.settled.duration",
          event_name: [:jido, :agent, :turn, :settled],
          tags: [:status, :stage],
          unit: {:native, :millisecond}
        ),
        Telemetry.Metrics.counter("jido.agent.admission.rejected.count",
          event_name: [:jido, :agent, :admission, :rejected],
          tags: [:admission_reason]
        ),
        Telemetry.Metrics.counter("jido.scheduler.delivery.count",
          event_name: [:jido, :scheduler, :delivery],
          tags: [:scheduler_outcome]
        ),
        Telemetry.Metrics.counter("jido.topology.ownership.settled.count",
          event_name: [:jido, :topology, :ownership, :settled],
          tags: [:status]
        )
      ]
  end

  @doc """
  Returns true when the optional OpenTelemetry mapping is active.

  The result is false when `opentelemetry_api` is absent, the Jido mapping is
  disabled, or the host has a no-op tracer. Jido does not start or configure an
  OpenTelemetry SDK.
  """
  @spec open_telemetry?() :: boolean()
  def open_telemetry?, do: OpenTelemetry.enabled?()

  @doc false
  @spec attach_default_handler() :: :ok
  def attach_default_handler do
    attach(@semantic_handler_id, semantic_terminal_events(), &__MODULE__.handle_semantic_event/4)
    :ok
  end

  @doc false
  def handle_semantic_event(event, measurements, metadata, _config) do
    metadata = Semantic.normalize_metadata(metadata)
    measurements = Semantic.normalize_measurements(measurements)
    mode = semantic_log_mode()

    if log_semantic?(mode, event, measurements, metadata) do
      message =
        "[jido.semantic] event=#{event |> Enum.drop(1) |> Enum.join(".")} " <>
          format_metadata(Map.merge(metadata, measurements))

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

  defp span_metrics({name, event, tags}) do
    for ending <- [:stop, :exception], metric <- [:count, :duration] do
      event_name = event ++ [ending]
      metric_name = "#{name}.#{ending}.#{metric}"

      case metric do
        :count ->
          Telemetry.Metrics.counter(metric_name, event_name: event_name, tags: tags)

        :duration ->
          Telemetry.Metrics.summary(metric_name,
            event_name: event_name,
            tags: tags,
            unit: {:native, :millisecond}
          )
      end
    end
  end

  defp semantic_terminal_events do
    span_events =
      for {_name, prefix, _tags} <- @span_metrics,
          ending <- [:stop, :exception],
          do: prefix ++ [ending]

    span_events ++
      [
        [:jido, :agent, :turn, :settled],
        [:jido, :agent, :admission, :rejected],
        [:jido, :scheduler, :delivery],
        [:jido, :topology, :ownership, :settled]
      ]
  end

  defp attach(id, events, handler) do
    case :telemetry.attach_many(id, events, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp semantic_log_mode do
    instance_mode =
      case Process.get(@log_scope_key) do
        instance when is_atom(instance) and not is_nil(instance) ->
          Debug.override(instance, :semantic_log_mode)

        _other ->
          nil
      end

    if instance_mode in [:off, :errors, :interesting, :all],
      do: instance_mode,
      else: configured_semantic_log_mode()
  end

  defp configured_semantic_log_mode do
    config = Application.get_env(:jido, :telemetry, [])

    case config_value(config, :semantic_log_mode) do
      mode when mode in [:off, :errors, :interesting, :all] -> mode
      _other -> :off
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
    native_to_ms(duration) >= semantic_slow_threshold_ms()
  end

  defp semantic_slow_threshold_ms do
    config = Application.get_env(:jido, :telemetry, [])

    case config_value(config, :semantic_slow_threshold_ms) do
      value when is_integer(value) and value >= 0 -> value
      _value -> 1_000
    end
  end

  defp format_metadata(metadata) do
    metadata
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{format_value(value)}" end)
  end

  defp format_value(value) when is_binary(value), do: truncate(value, 128)
  defp format_value(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp format_value(value), do: value |> inspect(limit: 10, printable_limit: 128) |> truncate(128)

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: String.slice(value, 0, max - 3) <> "..."

  defp native_to_ms(value) when is_integer(value) do
    System.convert_time_unit(value, :native, :microsecond) / 1_000
  end

  defp native_to_ms(_value), do: 0

  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil
end
