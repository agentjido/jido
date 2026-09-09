defmodule Jido.Telemetry do
  @moduledoc """
  Semantic logging, metrics, and optional tracing for the Jido runtime.

  Jido emits version-1 semantic events for Agent lifecycle, Turn result,
  commit, Directive work, Turn settlement, admission rejection, persistence,
  and static local Topology operations. Spans use `:start`, `:stop`, and
  `:exception`. Returned errors use `:stop`. Faults that escape the observed
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

  `metrics/0` returns low-cardinality semantic metrics. When the optional
  `opentelemetry_api` dependency and a host-managed SDK are available, the same
  events also create OpenTelemetry spans. Jido does not start an SDK or
  exporter.

  Handlers run in the emitting process and must return quickly. Abrupt process
  or VM loss can prevent final events, so this stream is not a durable journal.
  """

  require Logger

  alias Jido.Debug
  alias Jido.Telemetry.Formatter
  alias Jido.Telemetry.Semantic

  @typedoc "Supported telemetry event names."
  @type event_name :: [atom(), ...]

  @typedoc "Telemetry measurements map."
  @type measurements :: %{
          optional(:system_time) => integer(),
          optional(:duration) => integer(),
          atom() => term()
        }

  @typedoc "Telemetry metadata map."
  @type metadata :: %{atom() => term()}

  @semantic_handler_id "jido-semantic-logger"

  @doc """
  Attaches the semantic log handler.

  This function is idempotent and is safe to call more than once.
  """
  @spec setup() :: :ok
  def setup do
    attach(@semantic_handler_id, semantic_terminal_events(), &__MODULE__.handle_semantic_event/4)
    :ok
  end

  @doc """
  Returns low-cardinality metric definitions for the semantic event catalog.

  Wire these definitions into the reporter in the host application:

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

  @doc false
  def handle_semantic_event(event, measurements, metadata, _config) do
    metadata = Semantic.normalize_metadata(metadata)
    measurements = Semantic.normalize_measurements(measurements)
    mode = semantic_log_mode(metadata)

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

  defp semantic_log_mode(metadata) do
    instance_mode =
      case Map.get(metadata, :jido_instance) do
        instance when is_atom(instance) and not is_nil(instance) ->
          Debug.override(instance, :semantic_log_mode)

        _other ->
          nil
      end

    if instance_mode in [:off, :errors, :interesting, :all] do
      instance_mode
    else
      configured_semantic_log_mode()
    end
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
    Formatter.to_ms(duration) >= semantic_slow_threshold_ms()
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
end
