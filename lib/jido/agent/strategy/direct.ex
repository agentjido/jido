defmodule Jido.Agent.Strategy.Direct do
  @moduledoc """
  Default execution strategy that runs instructions immediately and sequentially.

  This strategy:
  - Executes each instruction via `Jido.Exec.run/1`
  - Merges results into agent state
  - Applies state operations (e.g., `StateOp.SetState`) to the agent
  - Returns only external directives to the caller
  - Optionally tracks instruction execution in Thread when `thread?` is enabled

  This is the default strategy and provides the simplest execution model.

  ## Thread Tracking

  When `thread?` option is enabled via `ctx[:strategy_opts][:thread?]` or if a thread
  already exists in agent state, the strategy will:
  - Ensure a Thread exists in agent state
  - Append `:instruction_start` entry before each instruction
  - Append `:instruction_end` entry after each instruction (with status :ok or :error)

  Example:
      agent = Agent.cmd(agent, MyAction, strategy_opts: [thread?: true])
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.StateOps
  alias Jido.Error
  alias Jido.Instruction
  alias Jido.Thread.Agent, as: ThreadAgent

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) when is_list(instructions) do
    agent = maybe_ensure_thread(agent, ctx)

    {final_agent, reversed_directives} =
      Enum.reduce(instructions, {agent, []}, fn instruction, {acc_agent, acc_directives} ->
        {new_agent, new_directives} = run_instruction_with_tracking(acc_agent, instruction)
        {new_agent, Enum.reverse(new_directives) ++ acc_directives}
      end)

    {final_agent, Enum.reverse(reversed_directives)}
  end

  defp maybe_ensure_thread(agent, ctx) do
    opts = ctx[:strategy_opts] || []
    thread_enabled? = Keyword.get(opts, :thread?, false)

    if thread_enabled? or ThreadAgent.has_thread?(agent) do
      ThreadAgent.ensure(agent)
    else
      agent
    end
  end

  defp run_instruction_with_tracking(agent, %Instruction{} = instruction) do
    if ThreadAgent.has_thread?(agent) do
      agent = append_instruction_start(agent, instruction)
      {agent, directives, status} = run_instruction(agent, instruction)
      agent = append_instruction_end(agent, instruction, status)
      {agent, directives}
    else
      {agent, directives, _status} = run_instruction(agent, instruction)
      {agent, directives}
    end
  end

  defp run_instruction(agent, %Instruction{} = instruction) do
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        {StateOps.apply_result(agent, result), [], :ok}

      {:ok, result, effects} when is_map(result) ->
        agent = StateOps.apply_result(agent, result)
        {agent, directives} = StateOps.apply_state_ops(agent, List.wrap(effects))
        {agent, directives, :ok}

      {:error, reason} ->
        error = Error.execution_error("Instruction failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :instruction}], :error}
    end
  end

  defp append_instruction_start(agent, %Instruction{} = instruction) do
    entry = %{
      kind: :instruction_start,
      payload: instruction_payload(instruction)
    }

    ThreadAgent.append(agent, entry)
  end

  defp append_instruction_end(agent, %Instruction{} = instruction, status) do
    entry = %{
      kind: :instruction_end,
      payload: Map.put(instruction_payload(instruction), :status, status)
    }

    ThreadAgent.append(agent, entry)
  end

  defp instruction_payload(%Instruction{} = instruction) do
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
end
