defmodule Jido.BehaviorTree.Telemetry do
  @moduledoc """
  Telemetry handler for Jido BehaviorTree events.

  This module provides optional telemetry integration for behavior tree execution.
  When started, it attaches handlers for `[:jido, :bt, ...]` events and logs
  execution details.

  ## Usage

  Add to your application's supervision tree:

      children = [
        {Jido.BehaviorTree.Telemetry, []}
      ]

  Or start manually:

      Jido.BehaviorTree.Telemetry.start_link([])

  ## Events

  This handler processes the following telemetry events:

  ### Node Events

  - `[:jido, :bt, :node, :tick, :start]` - Node tick started
  - `[:jido, :bt, :node, :tick, :stop]` - Node tick completed
  - `[:jido, :bt, :node, :tick, :exception]` - Node tick raised an exception
  - `[:jido, :bt, :node, :halt, :start]` - Node halt started
  - `[:jido, :bt, :node, :halt, :stop]` - Node halt completed
  - `[:jido, :bt, :node, :halt, :exception]` - Node halt raised an exception

  ## Configuration

  Configure log level via application config:

      config :jido, :behavior_tree_telemetry,
        log_level: :debug  # :debug, :info, :warning, :error, or false to disable

  Default log level is `:debug`.

  ## Metrics

  This module defines the following `Telemetry.Metrics` compatible metrics:

  - `jido.bt.node.tick.count` - Total node ticks executed
  - `jido.bt.node.tick.duration` - Duration of node ticks (nanoseconds)
  - `jido.bt.node.tick.exception.count` - Node tick failures
  - `jido.bt.node.halt.count` - Total node halts executed
  - `jido.bt.node.halt.duration` - Duration of node halts (nanoseconds)
  """

  use GenServer
  require Logger

  @handler_id "jido-behaviortree-telemetry"

  @doc """
  Returns a list of `Telemetry.Metrics` compatible metric definitions.

  Use this with your metrics reporter (e.g., Telemetry.Metrics.ConsoleReporter):

      metrics = Jido.BehaviorTree.Telemetry.metrics()
      Telemetry.Metrics.ConsoleReporter.start_link(metrics: metrics)
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      Telemetry.Metrics.counter(
        "jido.bt.node.tick.count",
        event_name: [:jido, :bt, :node, :tick, :stop],
        description: "Total number of node ticks executed"
      ),
      Telemetry.Metrics.sum(
        "jido.bt.node.tick.duration",
        event_name: [:jido, :bt, :node, :tick, :stop],
        measurement: :duration,
        unit: {:native, :nanosecond},
        description: "Total duration of node ticks"
      ),
      Telemetry.Metrics.counter(
        "jido.bt.node.tick.exception.count",
        event_name: [:jido, :bt, :node, :tick, :exception],
        description: "Total number of node tick failures"
      ),
      Telemetry.Metrics.counter(
        "jido.bt.node.halt.count",
        event_name: [:jido, :bt, :node, :halt, :stop],
        description: "Total number of node halts executed"
      ),
      Telemetry.Metrics.sum(
        "jido.bt.node.halt.duration",
        event_name: [:jido, :bt, :node, :halt, :stop],
        measurement: :duration,
        unit: {:native, :nanosecond},
        description: "Total duration of node halts"
      ),
      Telemetry.Metrics.counter(
        "jido.bt.node.halt.exception.count",
        event_name: [:jido, :bt, :node, :halt, :exception],
        description: "Total number of node halt failures"
      )
    ]
  end

  @doc """
  Returns the list of telemetry events this module handles.

  Useful for attaching your own handlers or for testing.
  """
  @spec events() :: [[atom()]]
  def events do
    [
      [:jido, :bt, :node, :tick, :start],
      [:jido, :bt, :node, :tick, :stop],
      [:jido, :bt, :node, :tick, :exception],
      [:jido, :bt, :node, :halt, :start],
      [:jido, :bt, :node, :halt, :stop],
      [:jido, :bt, :node, :halt, :exception]
    ]
  end

  @doc """
  Starts the telemetry handler.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the child spec for supervision trees.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl true
  def init(opts) do
    :telemetry.attach_many(
      @handler_id,
      events(),
      &__MODULE__.handle_event/4,
      opts
    )

    {:ok, opts}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  # Node tick events

  @doc false
  def handle_event([:jido, :bt, :node, :tick, :start], _measurements, metadata, _config) do
    if log_enabled?() do
      Logger.debug("[BT] Node tick started",
        agent_id: metadata[:agent_id],
        plugin: inspect(metadata[:plugin]),
        node: inspect(metadata[:node]),
        sequence: metadata[:sequence]
      )
    end
  end

  def handle_event([:jido, :bt, :node, :tick, :stop], measurements, metadata, _config) do
    if log_enabled?() do
      duration_us = div(Map.get(measurements, :duration, 0), 1000)

      Logger.debug("[BT] Node tick completed",
        agent_id: metadata[:agent_id],
        plugin: inspect(metadata[:plugin]),
        node: inspect(metadata[:node]),
        sequence: metadata[:sequence],
        status: inspect(metadata[:status]),
        duration_μs: duration_us
      )
    end
  end

  def handle_event([:jido, :bt, :node, :tick, :exception], measurements, metadata, _config) do
    if log_enabled?() do
      duration_us = div(Map.get(measurements, :duration, 0), 1000)

      Logger.warning("[BT] Node tick failed",
        agent_id: metadata[:agent_id],
        plugin: inspect(metadata[:plugin]),
        node: inspect(metadata[:node]),
        sequence: metadata[:sequence],
        duration_μs: duration_us,
        error: inspect(metadata[:error])
      )
    end
  end

  # Node halt events

  def handle_event([:jido, :bt, :node, :halt, :start], _measurements, metadata, _config) do
    if log_enabled?() do
      Logger.debug("[BT] Node halt started",
        node: inspect(metadata[:node])
      )
    end
  end

  def handle_event([:jido, :bt, :node, :halt, :stop], measurements, metadata, _config) do
    if log_enabled?() do
      duration_us = div(Map.get(measurements, :duration, 0), 1000)

      Logger.debug("[BT] Node halt completed",
        node: inspect(metadata[:node]),
        duration_μs: duration_us
      )
    end
  end

  def handle_event([:jido, :bt, :node, :halt, :exception], measurements, metadata, _config) do
    if log_enabled?() do
      duration_us = div(Map.get(measurements, :duration, 0), 1000)

      Logger.warning("[BT] Node halt failed",
        node: inspect(metadata[:node]),
        duration_μs: duration_us,
        error: inspect(metadata[:error])
      )
    end
  end

  defp log_enabled? do
    case Application.get_env(:jido, :behavior_tree_telemetry, [])[:log_level] do
      false -> false
      nil -> true
      _level -> true
    end
  end
end
