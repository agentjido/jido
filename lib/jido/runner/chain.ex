defmodule Jido.Runner.Chain do
  @moduledoc """
  A runner that executes instructions sequentially with support for result chaining,
  directive-based interruption, and syscall handling.

  ## Chain Execution
  Instructions are executed in sequence with the output of each instruction
  becoming the input for the next instruction in the chain. This enables
  data flow between instructions while maintaining state consistency.

  ## Directive Handling
  The chain supports directive-based flow control:
  * Directives can interrupt chain execution (default)
  * Directives can be collected while continuing execution
  * State changes and directives can be mixed in the chain

  ## Syscall Handling
  * Syscalls are special instructions that affect server behavior
  * Syscalls are validated before execution
  * Syscalls can be mixed with regular instructions
  * Chain execution continues after syscall handling

  ## State Management
  * Initial state flows through the chain
  * Each instruction can modify or extend the state
  * Final state reflects accumulated changes
  * Directive interrupts preserve current state
  """
  @behaviour Jido.Runner

  use ExDbug, enabled: false, truncate: false

  alias Jido.Instruction
  alias Jido.Runner.Result
  alias Jido.Agent.{Directive, Syscall}
  alias Jido.Error

  @type chain_result :: {:ok, Result.t()} | {:error, Error.t() | String.t()}
  @type chain_opts :: [continue_on_directive: boolean()]

  @doc """
  Executes a chain of instructions, handling directives, syscalls and state transitions.

  ## Execution Flow
  1. Instructions are executed in sequence
  2. Results from each instruction feed into the next
  3. Directives can interrupt or continue the chain
  4. Syscalls are validated and handled
  5. State changes are accumulated through the chain

  ## Parameters
    - agent: The agent struct containing pending instructions
    - opts: Optional keyword list of execution options:
      - :continue_on_directive - boolean, continues chain execution after directive (default: false)
      - :merge_results - boolean, merges map results into subsequent instruction params (default: true)

  ## Returns
    - `{:ok, %Result{}}` - Chain completed successfully
      - result_state: Final accumulated state
      - directives: List of encountered directives
      - syscalls: List of executed syscalls
      - status: Final execution status
    - `{:error, term()}` - Chain execution failed
      - Contains error details and partial results

  ## Examples

      # Basic chain execution
      {:ok, result} = Chain.run(agent)

      # Continue after directives
      {:ok, result} = Chain.run(agent, continue_on_directive: true)

      # Handle execution error
      {:error, error} = Chain.run(agent_with_failing_instruction)
  """
  @impl true
  @spec run(Jido.Agent.t(), chain_opts()) :: chain_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    dbug("Starting chain runner",
      agent_id: agent.id,
      opts: opts
    )

    case :queue.to_list(instructions) do
      [] ->
        dbug("No instructions found")

        result = %Result{
          initial_state: agent.state,
          instructions: [],
          result_state: agent.state,
          directives: [],
          syscalls: [],
          status: :ok
        }

        {:ok, result}

      instructions_list ->
        dbug("Found #{length(instructions_list)} instructions to execute")
        execute_chain(agent, instructions_list, opts)
    end
  end

  @spec execute_chain(Jido.Agent.t(), [Instruction.t()], keyword()) :: chain_result()
  defp execute_chain(agent, instructions_list, opts) do
    initial_result = %Result{
      initial_state: agent.state,
      instructions: instructions_list,
      result_state: agent.state,
      directives: [],
      syscalls: [],
      status: :ok
    }

    merge_results = Keyword.get(opts, :merge_results, true)
    chain_opts = Keyword.put(opts, :merge_results, merge_results)

    execute_chain_step(instructions_list, initial_result, chain_opts)
  end

  @spec execute_chain_step([Instruction.t()], Result.t(), keyword()) :: chain_result()
  defp execute_chain_step([], result, _opts) do
    dbug("Chain execution completed successfully")
    {:ok, result}
  end

  defp execute_chain_step([instruction | remaining], result, opts) do
    dbug("Executing chain step",
      instruction: instruction,
      current_state: result.result_state,
      instruction_params: instruction.params
    )

    case execute_instruction(instruction, result.result_state) do
      {:ok, maybe_directive} ->
        if Directive.is_directive?(maybe_directive) do
          handle_directive_result(maybe_directive, remaining, result, opts)
        else
          case maybe_directive do
            maybe_syscall when is_struct(maybe_syscall) ->
              if Syscall.is_syscall?(maybe_syscall) do
                handle_syscall_result(maybe_syscall, remaining, result, opts)
              else
                handle_state_result(maybe_directive, remaining, result, opts)
              end

            _ ->
              handle_state_result(maybe_directive, remaining, result, opts)
          end
        end

      {:error, error} ->
        dbug("Chain step failed",
          error: error,
          instruction: instruction
        )

        {:error, %{result | error: error, status: :error}}
    end
  end

  @spec execute_instruction(Instruction.t(), map()) ::
          {:ok, map() | Directive.t() | Syscall.t()} | {:error, term()}
  defp execute_instruction(%Instruction{action: action, params: params, context: context}, state) do
    dbug("Executing workflow",
      action: action,
      params: params,
      current_state: state
    )

    # IMPORTANT: Params should override state values
    merged_params = Map.merge(state, params)

    dbug("Executing with merged params",
      action: action,
      merged_params: merged_params,
      original_params: params
    )

    context = Map.put(context, :state, state)
    Jido.Workflow.run(action, merged_params, context)
  end

  @spec handle_directive_result(Directive.t(), [Instruction.t()], Result.t(), keyword()) ::
          chain_result()
  defp handle_directive_result(directive, remaining, result, opts) do
    dbug("Handling directive in chain",
      directive: directive,
      remaining_instructions: length(remaining)
    )

    updated_result = %{result | directives: result.directives ++ [directive], status: :ok}

    if Keyword.get(opts, :continue_on_directive, false) do
      dbug("Continuing chain after directive")
      execute_chain_step(remaining, updated_result, opts)
    else
      dbug("Interrupting chain due to directive")
      {:ok, updated_result}
    end
  end

  @spec handle_syscall_result(Syscall.t(), [Instruction.t()], Result.t(), keyword()) ::
          chain_result()
  defp handle_syscall_result(syscall, remaining, result, opts) do
    dbug("Handling syscall in chain",
      syscall: syscall,
      remaining_instructions: length(remaining)
    )

    case Syscall.validate_syscall(syscall) do
      :ok ->
        updated_result = %{result | syscalls: result.syscalls ++ [syscall], status: :ok}
        execute_chain_step(remaining, updated_result, opts)

      {:error, reason} ->
        dbug("Syscall validation failed", reason: reason)
        {:error, %{result | error: {:invalid_syscall, reason}, status: :error}}
    end
  end

  @spec handle_state_result(map(), [Instruction.t()], Result.t(), keyword()) ::
          chain_result()
  defp handle_state_result(new_state, remaining, result, opts) do
    dbug("Handling state transition in chain",
      previous_state: result.result_state,
      new_state: new_state,
      remaining_count: length(remaining)
    )

    updated_result = %{
      result
      | # Merge new_state with existing state instead of replacing
        result_state: Map.merge(result.result_state, new_state),
        status: :ok
    }

    dbug("Updated chain state",
      final_state: updated_result.result_state,
      remaining_instructions: length(remaining)
    )

    execute_chain_step(remaining, updated_result, opts)
  end
end
