defmodule Jido.Agent.Strategy.Direct do
  @moduledoc """
  Default execution strategy that runs instructions immediately and sequentially.

  This strategy:
  - Executes each instruction via `Jido.Exec.run/1`
  - Merges results into agent state
  - Applies state operations (e.g., `StateOp.SetState`) to the agent
  - Returns only external directives to the caller

  This is the default strategy and provides the simplest execution model.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.StateOps
  alias Jido.Error
  alias Jido.Instruction

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) when is_list(instructions) do
    {final_agent, reversed_directives} =
      Enum.reduce(instructions, {agent, []}, fn instruction, {acc_agent, acc_directives} ->
        {new_agent, new_directives} = run_instruction(acc_agent, instruction)
        {new_agent, Enum.reverse(new_directives) ++ acc_directives}
      end)

    {final_agent, Enum.reverse(reversed_directives)}
  end

  defp run_instruction(agent, %Instruction{} = instruction) do
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        {StateOps.apply_result(agent, result), []}

      {:ok, result, effects} when is_map(result) ->
        agent = StateOps.apply_result(agent, result)
        StateOps.apply_state_ops(agent, List.wrap(effects))

      {:error, reason} ->
        error = Error.execution_error("Instruction failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :instruction}]}
    end
  end
end
