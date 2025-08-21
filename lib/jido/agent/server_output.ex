defmodule Jido.Agent.Server.Output do
  @moduledoc false
  require Logger

  alias Jido.Signal
  alias Jido.Signal.Dispatch
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Util

  @type log_level ::
          :debug | :info | :notice | :warning | :error | :critical | :alert | :emergency

  @signal_log_levels %{
    categories: %{
      cmd: :debug,
      event: :info,
      err: :error,
      out: :debug
    },
    specific: %{
      # Command signals
      "jido.agent.cmd.state": :debug,
      "jido.agent.cmd.queuesize": :debug,

      # Event signals
      "jido.agent.event.started": :info,
      "jido.agent.event.stopped": :info,
      "jido.agent.event.transition.succeeded": :debug,
      "jido.agent.event.transition.failed": :warning,
      "jido.agent.event.queue.overflow": :warning,
      "jido.agent.event.queue.cleared": :debug,
      "jido.agent.event.process.started": :debug,
      "jido.agent.event.process.restarted": :notice,
      "jido.agent.event.process.terminated": :notice,
      "jido.agent.event.process.failed": :warning,

      # Error signals
      "jido.agent.err.execution.error": :error,

      # Output signals
      "jido.agent.out.instruction.result": :debug,
      "jido.agent.out.signal.result": :debug
    }
  }

  # No level by default - determined by signal type
  @default_dispatch {:logger, []}

  @doc """
  Logs a message at the specified level if it meets the agent's log level threshold.
  """
  @spec log(ServerState.t(), log_level(), String.t(), keyword()) ::
          :ok | {:ignored, :level_too_low}
  def log(%ServerState{} = state, level, message, metadata \\ []) when is_atom(level) do
    # Add agent context to metadata
    metadata = add_agent_metadata(state, metadata)

    # Use Jido.Util.cond_log to conditionally log based on threshold level
    Util.cond_log(state.log_level, level, message, metadata)
  end

  @doc """
  Emits a signal through the specified dispatch mechanism.

  Automatically determines the appropriate log level based on signal type.
  """
  @spec emit(Signal.t() | nil, ServerState.t(), keyword()) :: any()
  def emit(signal, state, opts \\ [])

  def emit(nil, _state, _opts) do
    {:error, :no_signal}
  end

  def emit(%Signal{} = signal, state, opts) do
    # Determine appropriate level based on signal type
    level = get_level_for_signal(signal)

    # Configure dispatch with the appropriate level
    base_dispatch = Keyword.get(opts, :dispatch) || signal.jido_dispatch || @default_dispatch
    dispatch_config = add_level_to_dispatch(base_dispatch, level)

    log(
      state,
      :debug,
      "Emit Signal [#{signal.id}] of type '#{signal.type}' from source '#{signal.source}'"
    )

    Dispatch.dispatch(signal, dispatch_config)
  end

  def emit(_invalid, _state, _opts) do
    {:error, :invalid_signal}
  end

  # Private helper functions

  # Add agent metadata to the log metadata
  defp add_agent_metadata(%ServerState{} = state, metadata) do
    if state.agent && state.agent.id do
      metadata
      |> Keyword.put_new(:agent_id, state.agent.id)
      |> Keyword.put_new(:agent_status, state.status)
    else
      metadata
    end
  end

  # Get the appropriate log level for a signal based on its type
  defp get_level_for_signal(%Signal{type: type}) do
    # Try to get specific level for this exact signal type
    specific_level = @signal_log_levels.specific[String.to_atom(type)]

    if specific_level do
      specific_level
    else
      # Fall back to category-based level
      case type do
        "jido.agent.cmd." <> _ -> @signal_log_levels.categories.cmd
        "jido.agent.event." <> _ -> @signal_log_levels.categories.event
        "jido.agent.err." <> _ -> @signal_log_levels.categories.err
        "jido.agent.out." <> _ -> @signal_log_levels.categories.out
        # Default to info if we can't determine
        _ -> :info
      end
    end
  end

  # Add level to dispatch configuration
  defp add_level_to_dispatch({target, dispatch_opts}, level) do
    {target, Keyword.put_new(dispatch_opts, :level, level)}
  end

  defp add_level_to_dispatch(other, _level), do: other
end
