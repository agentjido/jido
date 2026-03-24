defmodule Jido.Agent.Strategy.InstructionTracking do
  @moduledoc """
  Shared instruction-thread tracking helpers for strategy implementations.

  Appends `:instruction_start` / `:instruction_end` entries when a thread is
  present in the agent state and provides a consistent payload shape.
  """

  alias Jido.Agent
  alias Jido.Agent.StateOps
  alias Jido.Instruction
  alias Jido.Thread.Agent, as: ThreadAgent

  @doc """
  Append an `:instruction_start` thread entry.
  """
  @spec append_instruction_start(Agent.t(), Instruction.t()) :: Agent.t()
  def append_instruction_start(agent, %Instruction{} = instruction) do
    append_entry(agent, %{
      kind: :instruction_start,
      payload: instruction_payload(instruction)
    })
  end

  @doc """
  Append an `:instruction_end` thread entry.
  """
  @spec append_instruction_end(Agent.t(), Instruction.t(), atom()) :: Agent.t()
  def append_instruction_end(agent, %Instruction{} = instruction, status) do
    append_entry(agent, %{
      kind: :instruction_end,
      payload: Map.put(instruction_payload(instruction), :status, status)
    })
  end

  @doc """
  Conditionally append `:instruction_start` when thread tracking is enabled.
  """
  @spec maybe_append_instruction_start(Agent.t(), Instruction.t()) :: Agent.t()
  def maybe_append_instruction_start(agent, %Instruction{} = instruction) do
    if ThreadAgent.has_thread?(agent) do
      append_instruction_start(agent, instruction)
    else
      agent
    end
  end

  @doc """
  Conditionally append `:instruction_end` when thread tracking is enabled.
  """
  @spec maybe_append_instruction_end(Agent.t(), Instruction.t() | nil, atom()) :: Agent.t()
  def maybe_append_instruction_end(agent, nil, _status), do: agent

  def maybe_append_instruction_end(agent, %Instruction{} = instruction, status) do
    if ThreadAgent.has_thread?(agent) do
      append_instruction_end(agent, instruction, status)
    else
      agent
    end
  end

  @doc false
  @spec instruction_payload(Instruction.t()) :: map()
  def instruction_payload(%Instruction{} = instruction) do
    payload = %{action: instruction.action}

    payload =
      if is_map(instruction.params) and map_size(instruction.params) > 0 do
        Map.put(payload, :param_keys, Map.keys(instruction.params))
      else
        payload
      end

    if instruction.id do
      Map.put(payload, :instruction_id, instruction.id)
    else
      payload
    end
  end

  defp append_entry(agent, entry) do
    {agent, []} = StateOps.apply_state_ops(agent, [ThreadAgent.append_op(entry)])
    agent
  end
end
