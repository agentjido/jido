defmodule Jido.Agent.Strategy.Direct do
  @moduledoc """
  Default execution strategy that runs instructions immediately and sequentially.

  This strategy:
  - Executes each command at the `Jido.Exec.run/4` boundary
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
  alias Jido.Agent.Command
  alias Jido.Agent.Directive
  alias Jido.Observe.Config, as: ObserveConfig
  alias Jido.Agent.Strategy.InstructionTracking
  alias Jido.Agent.StateOps
  alias Jido.Error
  alias Jido.Thread.Agent, as: ThreadAgent

  @impl true
  def cmd(%Agent{} = agent, commands, ctx) when is_list(commands) do
    agent = maybe_ensure_thread(agent, ctx)

    {final_agent, reversed_directives} =
      Enum.reduce(commands, {agent, []}, fn command, {acc_agent, acc_directives} ->
        {new_agent, new_directives} = run_command_with_tracking(acc_agent, command, ctx)
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

  defp run_command_with_tracking(agent, %Command{} = command, ctx) do
    if ThreadAgent.has_thread?(agent) do
      agent = InstructionTracking.append_instruction_start(agent, command)
      {agent, directives, status} = run_command(agent, command, ctx)
      agent = InstructionTracking.append_instruction_end(agent, command, status)
      {agent, directives}
    else
      {agent, directives, _status} = run_command(agent, command, ctx)
      {agent, directives}
    end
  end

  defp run_command(agent, %Command{} = command, ctx) do
    runtime_context = %{
      state: agent.state,
      agent: agent,
      agent_server_pid: self()
    }

    exec_opts = ObserveConfig.action_exec_opts(ctx[:jido_instance], command.opts)

    case Command.run(command, runtime_context, exec_opts) do
      {:ok, result} when is_map(result) ->
        {StateOps.apply_result(agent, result), [], :ok}

      {:ok, result, effects} when is_map(result) ->
        agent = StateOps.apply_result(agent, result)
        {agent, directives} = StateOps.apply_state_ops(agent, List.wrap(effects))
        {agent, directives, :ok}

      {:error, reason} ->
        error = Error.execution_error("Instruction failed", details: %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :instruction}], :error}
    end
  end
end
