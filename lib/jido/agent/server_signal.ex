defmodule Jido.Agent.Server.Signal do
  @moduledoc false
  # Defines specialized signals for Agent Server communication and control.

  # This module provides functions for creating standardized signals used by the Agent Server
  # for operations like process management, state transitions, and command execution.
  use ExDbug, enabled: false

  alias Jido.Signal

  # Signal type prefixes
  @agent_prefix "jido.agent."
  @cmd_prefix "#{@agent_prefix}cmd."
  @syscall_prefix "#{@agent_prefix}syscall."
  @event_prefix "#{@agent_prefix}event."

  # Agent commands
  def cmd, do: "#{@cmd_prefix}"
  def get_topic, do: "#{@syscall_prefix}topic"
  def process_start, do: "#{@syscall_prefix}start"
  def process_list, do: "#{@syscall_prefix}list"
  def process_terminate, do: "#{@syscall_prefix}terminate"

  # Events
  def cmd_failed, do: "#{@event_prefix}cmd.failed"
  def cmd_success_with_syscall, do: "#{@event_prefix}cmd.syscall"
  def cmd_success_with_pending_instructions, do: "#{@event_prefix}cmd.pending_ix"
  def cmd_success, do: "#{@event_prefix}cmd.success"

  # Events - Process lifecycle
  def process_started, do: "#{@event_prefix}process.started"
  def process_terminated, do: "#{@event_prefix}process.terminated"
  def process_restart_succeeded, do: "#{@event_prefix}process.restart.succeeded"
  def process_restart_failed, do: "#{@event_prefix}process.restart.failed"
  def process_start_failed, do: "#{@event_prefix}process.start.failed"

  # Events - Queue processing
  def queue_overflow, do: "#{@event_prefix}queue.overflow"
  def queue_cleared, do: "#{@event_prefix}queue.cleared"
  def queue_processing_started, do: "#{@event_prefix}queue.processing.started"
  def queue_processing_completed, do: "#{@event_prefix}queue.processing.completed"
  def queue_processing_failed, do: "#{@event_prefix}queue.processing.failed"
  def queue_step_completed, do: "#{@event_prefix}queue.step.completed"
  def queue_step_ignored, do: "#{@event_prefix}queue.step.ignored"
  def queue_step_failed, do: "#{@event_prefix}queue.step.failed"

  # Events - Signal execution
  def signal_execution_started, do: "#{@event_prefix}signal.execution.started"
  def signal_execution_completed, do: "#{@event_prefix}signal.execution.completed"
  def signal_execution_failed, do: "#{@event_prefix}signal.execution.failed"

  # Events - State transitions
  def started, do: "#{@event_prefix}started"
  def stopped, do: "#{@event_prefix}stopped"
  def transition_succeeded, do: "#{@event_prefix}transition.succeeded"
  def transition_failed, do: "#{@event_prefix}transition.failed"

  def syscall_signal(state, type, payload \\ %{}) do
    build_signal(type, state.agent.id, payload)
  end

  @doc """
  Creates an event signal from agent state. Returns {:ok, Signal.t()} | {:error, String.t()}.
  """
  def event_signal(state, type, payload \\ %{}) do
    build_signal(type, state.agent.id, payload)
  end

  @doc """
  Converts actions into a command signal. Returns {:ok, Signal.t()} | {:error, String.t()}.
  """
  def action_signal(agent_id, action, args \\ %{}, opts \\ []) do
    normalized_actions = normalize_actions(action)

    build_signal(cmd(), agent_id, args,
      jido_instructions: normalized_actions,
      jido_opts: %{apply_state: Keyword.get(opts, :apply_state, true)}
    )
  end

  @doc """
  Extracts actions and options from a signal.
  """
  def extract_actions(%Signal{} = signal) do
    case {signal.jido_instructions, signal.jido_opts} do
      {instructions, opts} when is_list(instructions) and is_map(opts) ->
        {:ok, {instructions, signal.data, [apply_state: Map.get(opts, :apply_state, true)]}}

      _ ->
        {:error, :invalid_signal_format}
    end
  end

  @doc """
  Predicates for signal type checking.
  """
  def is_agent_signal?(%Signal{type: @agent_prefix <> _}), do: true
  def is_agent_signal?(_), do: false

  def is_syscall_signal?(%Signal{type: @syscall_prefix <> _}), do: true
  def is_syscall_signal?(_), do: false

  def is_event_signal?(%Signal{type: @event_prefix <> _}), do: true
  def is_event_signal?(_), do: false

  def is_process_signal?(%Signal{type: type}) do
    type in [process_start(), process_terminate()]
  end

  # Private Helpers
  defp build_signal(type, subject, data, extra_fields \\ %{})
       when is_binary(type) and is_binary(subject) and
              (is_map(extra_fields) or is_list(extra_fields)) do
    base = %{
      type: type,
      source: "jido",
      subject: subject,
      data: if(is_list(data), do: Map.new(data), else: data)
    }

    attrs = Map.merge(Map.new(extra_fields), base)

    Signal.new(attrs)
  end

  defp normalize_actions(action) when is_atom(action), do: [{action, %{}}]

  defp normalize_actions({action, args}) when is_atom(action) and is_map(args),
    do: [{action, args}]

  defp normalize_actions(actions) when is_list(actions) do
    Enum.map(actions, fn
      action when is_atom(action) -> {action, %{}}
      {action, args} when is_atom(action) and is_map(args) -> {action, args}
    end)
  end
end
