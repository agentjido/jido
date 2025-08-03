defmodule Jido.Telemetry do
  @moduledoc """
  Handles telemetry events for the Jido application.

  This module provides a centralized way to handle and report telemetry events
  throughout the application. It implements common telemetry patterns and provides
  a consistent interface for event handling.
  """

  use GenServer
  require Logger

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
          optional(:error) => term(),
          optional(:result) => term(),
          atom() => term()
        }

  @doc """
  Starts the telemetry handler.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Define metrics
    [
      # Operation metrics
      Telemetry.Metrics.counter(
        "jido.operation.count",
        description: "Total number of operations"
      ),
      Telemetry.Metrics.sum(
        "jido.operation.duration",
        unit: {:native, :millisecond},
        description: "Total duration of operations"
      ),
      Telemetry.Metrics.sum(
        "jido.operation.error.count",
        description: "Total number of operation errors"
      ),
      Telemetry.Metrics.last_value(
        "jido.operation.duration.max",
        unit: {:native, :millisecond},
        description: "Maximum duration of operations"
      )
    ]

    # Attach custom handlers
    :telemetry.attach_many(
      "jido-metrics",
      [
        [:jido, :operation, :start],
        [:jido, :operation, :stop],
        [:jido, :operation, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, opts}
  end

  @doc """
  Handles telemetry events.
  """
  @spec handle_event(event_name(), measurements(), metadata(), config :: term()) :: :ok
  def handle_event([:jido, :operation, :start], _measurements, _metadata, _config) do
    Logger.info("Operation started")
  end

  def handle_event([:jido, :operation, :stop], measurements, _metadata, _config) do
    duration = Map.get(measurements, :duration, 0)
    Logger.info("Operation completed in #{duration}ms")
  end

  def handle_event(
        [:jido, :operation, :exception],
        _measurements,
        %{error: error},
        _config
      ) do
    Logger.warning("Operation failed: #{inspect(error)}")
  end

  @doc """
  Executes a function while emitting telemetry events for its execution.
  """
  @spec span(String.t(), (-> result)) :: result when result: term()
  def span(operation_name, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:jido, :operation, :start],
      %{system_time: System.system_time()},
      %{operation: operation_name}
    )

    try do
      result = func.()

      :telemetry.execute(
        [:jido, :operation, :stop],
        %{
          duration: System.monotonic_time() - start_time
        },
        %{operation: operation_name, result: result}
      )

      result
    catch
      kind, reason ->
        stack = __STACKTRACE__

        :telemetry.execute(
          [:jido, :operation, :exception],
          %{
            duration: System.monotonic_time() - start_time
          },
          %{
            operation: operation_name,
            kind: kind,
            error: reason,
            stacktrace: stack
          }
        )

        :erlang.raise(kind, reason, stack)
    end
  end
end
