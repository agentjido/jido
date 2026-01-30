defmodule Jido.Telemetry do
  @moduledoc """
  Handles telemetry events for Jido Agent and Strategy operations.

  This module provides telemetry integration for agent command execution
  and strategy lifecycle events. It tracks execution time, success/failure
  rates, and provides debugging insights.

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

  ## Metadata

  All events include metadata about the agent, action, and strategy:
  - `:agent_id` - The agent's unique identifier
  - `:agent_module` - The agent module name
  - `:strategy` - The strategy module name
  - `:action` - The action being executed (for cmd events)
  - `:directive_count` - Number of directives produced (for stop events)
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
          optional(:agent_id) => String.t(),
          optional(:agent_module) => module(),
          optional(:strategy) => module(),
          optional(:action) => term(),
          optional(:directive_count) => non_neg_integer(),
          optional(:error) => term(),
          atom() => term()
        }

  @doc """
  Starts the telemetry handler.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Define metrics
    [
      # Agent command metrics
      Telemetry.Metrics.counter(
        "jido.agent.cmd.count",
        description: "Total number of agent commands executed"
      ),
      Telemetry.Metrics.sum(
        "jido.agent.cmd.duration",
        unit: {:native, :millisecond},
        description: "Total duration of agent commands"
      ),
      Telemetry.Metrics.counter(
        "jido.agent.cmd.exception.count",
        description: "Total number of agent command failures"
      ),
      Telemetry.Metrics.last_value(
        "jido.agent.cmd.duration.max",
        unit: {:native, :millisecond},
        description: "Maximum duration of agent commands"
      ),
      Telemetry.Metrics.sum(
        "jido.agent.cmd.directives.total",
        description: "Total number of directives produced"
      ),

      # Strategy init metrics
      Telemetry.Metrics.counter(
        "jido.agent.strategy.init.count",
        description: "Total number of strategy initializations"
      ),
      Telemetry.Metrics.sum(
        "jido.agent.strategy.init.duration",
        unit: {:native, :millisecond},
        description: "Total duration of strategy initializations"
      ),

      # Strategy cmd metrics
      Telemetry.Metrics.counter(
        "jido.agent.strategy.cmd.count",
        description: "Total number of strategy command executions"
      ),
      Telemetry.Metrics.sum(
        "jido.agent.strategy.cmd.duration",
        unit: {:native, :millisecond},
        description: "Total duration of strategy commands"
      ),

      # Strategy tick metrics
      Telemetry.Metrics.counter(
        "jido.agent.strategy.tick.count",
        description: "Total number of strategy ticks"
      ),
      Telemetry.Metrics.sum(
        "jido.agent.strategy.tick.duration",
        unit: {:native, :millisecond},
        description: "Total duration of strategy ticks"
      ),

      # AgentServer signal metrics
      Telemetry.Metrics.counter(
        "jido.agent_server.signal.count",
        description: "Total number of signals processed"
      ),
      Telemetry.Metrics.sum(
        "jido.agent_server.signal.duration",
        unit: {:native, :millisecond},
        description: "Total duration of signal processing"
      ),
      Telemetry.Metrics.counter(
        "jido.agent_server.signal.exception.count",
        description: "Total number of signal processing failures"
      ),

      # AgentServer directive metrics
      Telemetry.Metrics.counter(
        "jido.agent_server.directive.count",
        description: "Total number of directives executed"
      ),
      Telemetry.Metrics.sum(
        "jido.agent_server.directive.duration",
        unit: {:native, :millisecond},
        description: "Total duration of directive execution"
      ),
      Telemetry.Metrics.counter(
        "jido.agent_server.directive.exception.count",
        description: "Total number of directive execution failures"
      ),

      # AgentServer queue metrics
      Telemetry.Metrics.counter(
        "jido.agent_server.queue.overflow.count",
        description: "Total number of queue overflows"
      )
    ]

    # Attach custom handlers
    :telemetry.attach_many(
      "jido-agent-metrics",
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
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, opts}
  end

  @doc """
  Handles telemetry events for agent and strategy operations.
  """
  @spec handle_event(event_name(), measurements(), metadata(), config :: term()) :: :ok
  def handle_event([:jido, :agent, :cmd, :start], _measurements, metadata, _config) do
    Logger.debug("[Agent] Command started",
      agent_id: metadata[:agent_id],
      agent_module: metadata[:agent_module],
      action: inspect(metadata[:action])
    )
  end

  def handle_event([:jido, :agent, :cmd, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.debug("[Agent] Command completed",
      agent_id: metadata[:agent_id],
      agent_module: metadata[:agent_module],
      duration_μs: duration,
      directive_count: metadata[:directive_count]
    )
  end

  def handle_event([:jido, :agent, :cmd, :exception], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.warning("[Agent] Command failed",
      agent_id: metadata[:agent_id],
      agent_module: metadata[:agent_module],
      duration_μs: duration,
      error: inspect(metadata[:error])
    )
  end

  def handle_event([:jido, :agent, :strategy, :init, :start], _measurements, metadata, _config) do
    Logger.debug("[Strategy] Initialization started",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy]
    )
  end

  def handle_event([:jido, :agent, :strategy, :init, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.debug("[Strategy] Initialization completed",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      duration_μs: duration
    )
  end

  def handle_event(
        [:jido, :agent, :strategy, :init, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.warning("[Strategy] Initialization failed",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      duration_μs: duration,
      error: inspect(metadata[:error])
    )
  end

  def handle_event([:jido, :agent, :strategy, :cmd, :start], _measurements, metadata, _config) do
    Logger.debug("[Strategy] Command execution started",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      instruction_count: metadata[:instruction_count]
    )
  end

  def handle_event([:jido, :agent, :strategy, :cmd, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.debug("[Strategy] Command execution completed",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      duration_μs: duration,
      directive_count: metadata[:directive_count]
    )
  end

  def handle_event(
        [:jido, :agent, :strategy, :cmd, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.warning("[Strategy] Command execution failed",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      duration_μs: duration,
      error: inspect(metadata[:error])
    )
  end

  def handle_event([:jido, :agent, :strategy, :tick, :start], _measurements, metadata, _config) do
    Logger.debug("[Strategy] Tick started",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy]
    )
  end

  def handle_event([:jido, :agent, :strategy, :tick, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.debug("[Strategy] Tick completed",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      duration_μs: duration
    )
  end

  def handle_event(
        [:jido, :agent, :strategy, :tick, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.warning("[Strategy] Tick failed",
      agent_id: metadata[:agent_id],
      strategy: metadata[:strategy],
      duration_μs: duration,
      error: inspect(metadata[:error])
    )
  end

  # ---------------------------------------------------------------------------
  # AgentServer Event Handlers
  # ---------------------------------------------------------------------------

  def handle_event([:jido, :agent_server, :signal, :start], _measurements, metadata, _config) do
    Logger.debug("[AgentServer] Signal processing started",
      agent_id: metadata[:agent_id],
      signal_type: metadata[:signal_type]
    )
  end

  def handle_event([:jido, :agent_server, :signal, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.debug("[AgentServer] Signal processing completed",
      agent_id: metadata[:agent_id],
      signal_type: metadata[:signal_type],
      duration_μs: duration,
      directive_count: metadata[:directive_count]
    )
  end

  def handle_event(
        [:jido, :agent_server, :signal, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.warning("[AgentServer] Signal processing failed",
      agent_id: metadata[:agent_id],
      signal_type: metadata[:signal_type],
      duration_μs: duration,
      error: inspect(metadata[:error])
    )
  end

  def handle_event([:jido, :agent_server, :directive, :start], _measurements, metadata, _config) do
    Logger.debug("[AgentServer] Directive execution started",
      agent_id: metadata[:agent_id],
      directive_type: metadata[:directive_type]
    )
  end

  def handle_event([:jido, :agent_server, :directive, :stop], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.debug("[AgentServer] Directive execution completed",
      agent_id: metadata[:agent_id],
      directive_type: metadata[:directive_type],
      duration_μs: duration,
      result: metadata[:result]
    )
  end

  def handle_event(
        [:jido, :agent_server, :directive, :exception],
        measurements,
        metadata,
        _config
      ) do
    duration = Map.get(measurements, :duration, 0) |> to_microseconds()

    Logger.warning("[AgentServer] Directive execution failed",
      agent_id: metadata[:agent_id],
      directive_type: metadata[:directive_type],
      duration_μs: duration,
      error: inspect(metadata[:error])
    )
  end

  def handle_event([:jido, :agent_server, :queue, :overflow], measurements, metadata, _config) do
    Logger.warning("[AgentServer] Queue overflow",
      agent_id: metadata[:agent_id],
      signal_type: metadata[:signal_type],
      queue_size: measurements[:queue_size]
    )
  end

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
      action: action
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
      strategy: strategy_module
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

  # Convert native monotonic time to microseconds for logging
  defp to_microseconds(native_duration) do
    System.convert_time_unit(native_duration, :native, :microsecond)
  end
end
