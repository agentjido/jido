defmodule Jido.Telemetry do
  @moduledoc """
  The public runtime observability API.

  AgentServer emits Turn spans and lifecycle, commit, Directive, effects, and
  settlement point events under `[:jido, :agent_server]`. Persistence emits
  operation spans.

  Turn stop and settlement report the evaluation and commit result. Effects
  can finish later. The effects stop event reports their bounded result; an
  effects failure does not undo the committed Agent or its revision.

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
  @log_modes [:off, :errors, :interesting, :all]

  @span_metrics [
    {[:jido, :agent_server, :turn], [:stop], [:status, :stage]},
    {[:jido, :persistence, :operation], [:stop, :exception],
     [:operation, :status, :persistence_reason]}
  ]

  @point_metrics [
    {[:jido, :agent_server, :lifecycle, :start], []},
    {[:jido, :agent_server, :lifecycle, :stop], []},
    {[:jido, :agent_server, :commit], [:status]},
    {[:jido, :agent_server, :directives, :returned], []},
    {[:jido, :agent_server, :effects, :start], []},
    {[:jido, :agent_server, :effects, :stop], [:status, :stage]},
    {[:jido, :agent_server, :turn, :settled], [:status, :stage]}
  ]

  @typedoc "A Jido telemetry event name."
  @type event_name :: [atom(), ...]

  @typedoc "A Jido telemetry measurement map."
  @type measurements :: %{optional(atom()) => integer()}

  @typedoc "A Jido telemetry metadata map."
  @type metadata :: %{atom() => term()}

  @doc """
  Returns metric definitions for the Jido semantic event catalog.

  Turn stop and persistence span endings have count and duration metrics.
  Lifecycle, commit, returned Directives, effects, and settlement have counters
  only. Point events do not measure duration. Each counter counts events, not
  the number of Directives in an event.

  Tags use bounded status, stage, and operation values. They do not contain
  Agent, Signal, Turn, trace, module, or error IDs.

  Pass the returned list to a `Telemetry.Metrics` compatible reporter in the
  host application.
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    Enum.flat_map(@span_metrics, &span_metrics/1) ++
      Enum.map(@point_metrics, fn {event, tags} ->
        Telemetry.Metrics.counter(Enum.join(event ++ [:count], "."),
          event_name: event,
          tags: tags
        )
      end)
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
    attach(@semantic_handler_id, semantic_events(), &__MODULE__.handle_semantic_event/4)
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

  defp span_metrics({event, endings, tags}) do
    for ending <- endings, metric <- [:count, :duration] do
      event_name = event ++ [ending]
      metric_name = Enum.join(event_name ++ [metric], ".")

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

  defp semantic_events do
    metrics() |> Enum.map(& &1.event_name) |> Enum.uniq()
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

    if instance_mode in @log_modes,
      do: instance_mode,
      else: configured_semantic_log_mode()
  end

  defp configured_semantic_log_mode do
    config = Application.get_env(:jido, :telemetry, [])

    case config_value(config, :semantic_log_mode) do
      mode when mode in @log_modes -> mode
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

    System.convert_time_unit(duration, :native, :microsecond) / 1_000 >=
      semantic_slow_threshold_ms()
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
  defp format_value(value), do: to_string(value)

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: String.slice(value, 0, max - 3) <> "..."

  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil
end
