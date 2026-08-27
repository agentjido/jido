defmodule Jido.Agent.Strategy.InstructionTracking do
  @moduledoc """
  Shared instruction-thread tracking helpers for strategy implementations.

  Appends `:instruction_start` / `:instruction_end` entries when a thread is
  present in the agent state and provides a consistent payload shape.
  """

  alias Jido.Agent
  alias Jido.Agent.Command
  alias Jido.Thread.Agent, as: ThreadAgent

  @doc """
  Append an `:instruction_start` thread entry.
  """
  @spec append_instruction_start(Agent.t(), Command.t()) :: Agent.t()
  def append_instruction_start(agent, %Command{} = command) do
    entry = %{
      kind: :instruction_start,
      payload: instruction_payload(command)
    }

    ThreadAgent.append(agent, entry)
  end

  @doc """
  Append an `:instruction_end` thread entry.
  """
  @spec append_instruction_end(Agent.t(), Command.t(), atom()) :: Agent.t()
  def append_instruction_end(agent, %Command{} = command, status) do
    entry = %{
      kind: :instruction_end,
      payload: Map.put(instruction_payload(command), :status, status)
    }

    ThreadAgent.append(agent, entry)
  end

  @doc """
  Conditionally append `:instruction_start` when thread tracking is enabled.
  """
  @spec maybe_append_instruction_start(Agent.t(), Command.t()) :: Agent.t()
  def maybe_append_instruction_start(agent, %Command{} = command) do
    if ThreadAgent.has_thread?(agent) do
      append_instruction_start(agent, command)
    else
      agent
    end
  end

  @doc """
  Conditionally append `:instruction_end` when thread tracking is enabled.
  """
  @spec maybe_append_instruction_end(Agent.t(), Command.t() | nil, atom()) :: Agent.t()
  def maybe_append_instruction_end(agent, nil, _status), do: agent

  def maybe_append_instruction_end(agent, %Command{} = command, status) do
    if ThreadAgent.has_thread?(agent) do
      append_instruction_end(agent, command, status)
    else
      agent
    end
  end

  @doc false
  @spec instruction_payload(Command.t()) :: map()
  def instruction_payload(%Command{} = command) do
    payload = %{action: command.action}

    payload =
      if is_map(command.params) and map_size(command.params) > 0 do
        Map.put(payload, :param_keys, Map.keys(command.params))
      else
        payload
      end

    if command.metadata[:id] do
      Map.put(payload, :instruction_id, command.metadata[:id])
    else
      payload
    end
  end
end
