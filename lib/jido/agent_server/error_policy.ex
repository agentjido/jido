defmodule Jido.AgentServer.ErrorPolicy do
  @moduledoc false
  # Handles error directives according to the configured error policy.
  #
  # Policies:
  # - `:log_only` - Log the error and continue
  # - `:stop_on_error` - Log and stop the agent
  # - `{:emit_signal, dispatch_cfg}` - Emit an error signal
  # - `{:max_errors, n}` - Stop after n errors
  # - `fun/2` - Custom function

  require Logger

  alias Jido.Agent.Directive.Error, as: ErrorDirective
  alias Jido.AgentServer.State
  alias Jido.Runtime.Tasking
  alias Jido.Signal.Dispatch, as: SignalDispatch

  @type result :: {:ok, State.t()} | {:stop, term(), State.t()}

  @doc """
  Handle an error directive according to the configured policy.
  """
  @spec handle(ErrorDirective.t(), State.t()) :: result()
  def handle(%ErrorDirective{error: error, context: context}, state) do
    case state.error_policy do
      :log_only ->
        log_error(error, context, state)
        {:ok, state}

      :stop_on_error ->
        log_error(error, context, state)
        Logger.error("Agent #{state.id} stopping due to error policy")
        {:stop, {:agent_error, error}, state}

      {:emit_signal, dispatch_cfg} ->
        emit_error_signal(error, context, state, dispatch_cfg)
        {:ok, state}

      {:max_errors, max} ->
        handle_max_errors(error, context, state, max)

      fun when is_function(fun, 2) ->
        handle_custom_policy(fun, error, context, state)

      _ ->
        log_error(error, context, state)
        {:ok, state}
    end
  end

  defp log_error(error, context, state) do
    message = extract_message(error)
    context_str = if context, do: " [#{context}]", else: ""

    Logger.error("Agent #{state.id}#{context_str}: #{message}")
  end

  defp extract_message(%{message: message}) when is_binary(message), do: message
  defp extract_message(%{message: %{message: message}}) when is_binary(message), do: message
  defp extract_message(error), do: inspect(error)

  defp emit_error_signal(error, context, state, dispatch_cfg) do
    signal = build_error_signal(error, context, state)

    if Code.ensure_loaded?(SignalDispatch) do
      start_error_signal_task(signal, dispatch_cfg, state)
    else
      Logger.warning("Jido.Signal.Dispatch not available, skipping error signal emit")
    end
  end

  defp start_error_signal_task(signal, dispatch_cfg, state) do
    case Tasking.start_child(
           fn ->
             SignalDispatch.dispatch(signal, dispatch_cfg)
           end,
           jido: state.jido
         ) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Agent #{state.id} failed to emit error signal asynchronously: #{inspect(reason)}"
        )
    end
  end

  defp build_error_signal(error, context, state) do
    Jido.Signal.new!(%{
      type: "jido.agent.error",
      source: "/agent/#{state.id}",
      data: %{
        error: extract_message(error),
        context: context,
        agent_id: state.id
      }
    })
  end

  defp handle_max_errors(error, context, state, max) do
    state = State.increment_error_count(state)
    count = state.error_count

    if count >= max do
      log_error(error, context, state)
      Logger.error("Agent #{state.id} exceeded max errors (#{count}/#{max}), stopping")
      {:stop, {:max_errors_exceeded, count}, state}
    else
      Logger.warning("Agent #{state.id} error #{count}/#{max}: #{extract_message(error)}")
      {:ok, state}
    end
  end

  defp handle_custom_policy(fun, error, context, state) do
    error_directive = %ErrorDirective{error: error, context: context}

    try do
      case fun.(error_directive, state) do
        {:ok, %State{} = new_state} ->
          {:ok, new_state}

        {:stop, reason, %State{} = new_state} ->
          {:stop, reason, new_state}

        other ->
          Logger.error("Custom error policy returned invalid result: #{inspect(other)}")
          {:ok, state}
      end
    rescue
      e ->
        Logger.error("Custom error policy crashed: #{Exception.message(e)}")
        {:ok, state}
    catch
      kind, reason ->
        Logger.error("Custom error policy failed: #{kind} - #{inspect(reason)}")
        {:ok, state}
    end
  end
end
