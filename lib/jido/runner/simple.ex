defmodule Jido.Runner.Simple do
  @moduledoc """
  A simple runner that executes a single instruction from an Agent's instruction queue.

  ## Overview

  The Simple Runner follows a sequential execution model:
  1. Dequeues a single instruction from the agent's pending queue
  2. Executes the instruction via its action module
  3. Processes the result (either a state update, directive or both)
  4. Applies state changes if configured
  5. Returns the updated agent with the execution results and server directives

  ## Features
  * Single instruction execution
  * Support for directives and state results
  * Atomic execution guarantees
  * Comprehensive error handling
  * Debug logging at key execution points
  * Optional state application

  ## Error Handling
  * Invalid instructions are rejected
  * Action execution failures return error results
  * Queue empty condition handled gracefully
  * All errors preserve the original agent state
  """
  @behaviour Jido.Runner

  alias Jido.Instruction
  alias Jido.Error
  alias Jido.Agent.Directive

  @type run_opts :: [apply_directives?: boolean(), log_level: atom(), timeout: non_neg_integer()]
  @type run_result :: {:ok, Jido.Agent.t(), list()} | {:error, Error.t()}

  @doc """
  Executes a single instruction from the Agent's pending instructions queue.

  ## Execution Process
  1. Dequeues the oldest instruction from the agent's queue
  2. Creates a new Result struct to track execution
  3. Executes the instruction through its action module
  4. Processes any directives from the execution
  5. Optionally applies state changes
  6. Returns the updated agent with execution results and server directives

  ## Parameters
    * `agent` - The agent struct containing:
      * `pending_instructions` - Queue of pending instructions
      * `state` - Current agent state
      * `id` - Agent identifier
    * `opts` - Optional keyword list of execution options:
      * `apply_directives?` - When true (default), applies directives during execution
      * `timeout` - Timeout in milliseconds for action execution (merged with instruction opts)
      * `log_level` - Log level for debugging output

  ## Returns
    * `{:ok, updated_agent, directives}` - Successful execution with:
      * Updated state map (for state results)
      * Updated pending instructions queue
      * Any server directives from the execution
    * `{:error, reason}` - Execution failed with:
      * String error for queue empty condition
      * Error struct with details for execution failures

  ## Examples

      # Successful state update
      {:ok, updated_agent, directives} = Runner.Simple.run(agent_with_state_update)

      # Execute without applying directives
      {:ok, updated_agent, directives} = Runner.Simple.run(agent_with_state_update, apply_directives?: false)

      # Execute with custom timeout (runner opts are merged with instruction opts)
      {:ok, updated_agent, directives} = Runner.Simple.run(agent, timeout: 60_000)

      # Empty queue - returns agent unchanged
      {:ok, agent, []} = Runner.Simple.run(agent_with_empty_queue)

      # Execution error
      {:error, error} = Runner.Simple.run(agent_with_failing_action)

  ## Option Merging
    * Runner options are merged with each instruction's options
    * Instruction options take precedence over runner options
    * This allows per-instruction customization while providing defaults

  ## Error Handling
    * Returns `{:error, "No pending instructions"}` for empty queue
    * Returns `{:error, error}` with error details for execution failures
    * All errors preserve the original agent state
    * Failed executions do not affect the remaining queue

  ## Logging
  Debug logs are emitted at key points:
    * Runner start with agent ID
    * Instruction dequeue result
    * Execution setup and action invocation
    * Result processing and categorization
  """
  @impl true
  @spec run(Jido.Agent.t(), run_opts()) :: run_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    case :queue.out(instructions) do
      {{:value, %Instruction{} = instruction}, remaining} ->
        agent = %{agent | pending_instructions: remaining}
        execute_instruction(agent, instruction, opts)

      {:empty, _} ->
        {:ok, agent, []}
    end
  end

  @doc false
  @spec execute_instruction(Jido.Agent.t(), Instruction.t(), keyword()) :: run_result()
  defp execute_instruction(agent, instruction, opts) do
    # Inject agent state and merge runtime opts with instruction opts
    # Instruction opts take precedence over runner opts
    merged_opts = Keyword.merge(opts, instruction.opts)

    instruction = %{
      instruction
      | context: Map.put(instruction.context, :state, agent.state),
        opts: merged_opts
    }

    case Jido.Exec.run(instruction) do
      {:ok, result, directives} when is_list(directives) ->
        handle_directive_result(agent, result, directives, opts)

      {:ok, result, directive} ->
        handle_directive_result(agent, result, [directive], opts)

      {:ok, result} ->
        {:ok, %{agent | result: result}, []}

      {:error, %_{} = error, _dirs} ->
        {:error, error}

      {:error, %_{} = error} ->
        {:error, error}
    end
  end

  @spec handle_directive_result(Jido.Agent.t(), term(), list(), keyword()) :: run_result()
  defp handle_directive_result(agent, result, directives, opts) do
    apply_directives? = Keyword.get(opts, :apply_directives?, true)

    if apply_directives? do
      case Directive.apply_agent_directive(agent, directives) do
        {:ok, updated_agent, server_directives} ->
          {:ok, %{updated_agent | result: result}, server_directives}

        {:error, %_{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.new(:validation_error, "Invalid directive", %{reason: reason})}
      end
    else
      {:ok, %{agent | result: result}, directives}
    end
  end
end
