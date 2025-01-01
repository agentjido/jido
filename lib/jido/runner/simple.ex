defmodule Jido.Runner.Simple do
  @moduledoc """
  A simple runner that executes a single instruction from an Agent's instruction queue.

  ## Overview

  The Simple Runner follows a sequential execution model:
  1. Dequeues a single instruction from the agent's pending queue
  2. Executes the instruction via its action module
  3. Processes the result (either a directive, syscall or state update)
  4. Returns a Result struct containing the execution outcome

  ## Features
  * Single instruction execution
  * Support for directives, syscalls and state results
  * Atomic execution guarantees
  * Comprehensive error handling
  * Debug logging at key execution points

  ## Error Handling
  * Invalid instructions are rejected
  * Action execution failures return error results
  * Queue empty condition handled gracefully
  * All errors preserve the original agent state
  """
  @behaviour Jido.Runner

  use ExDbug, enabled: false, truncate: false

  alias Jido.Instruction
  alias Jido.Runner.Result
  alias Jido.Agent.{Directive, Syscall}
  alias Jido.Error

  @type run_opts :: keyword()
  @type run_result :: {:ok, Result.t()} | {:error, Error.t() | String.t()}

  @doc """
  Executes a single instruction from the Agent's pending instructions queue.

  ## Execution Process
  1. Dequeues the oldest instruction from the agent's queue
  2. Creates a new Result struct to track execution
  3. Executes the instruction through its action module
  4. Processes the execution result (directive, syscall or state)
  5. Returns the final Result struct

  ## Parameters
    * `agent` - The agent struct containing:
      * `pending_instructions` - Queue of pending instructions
      * `state` - Current agent state
      * `id` - Agent identifier
    * `opts` - Optional keyword list of execution options:
      * Currently unused but reserved for future extensions

  ## Returns
    * `{:ok, %Result{}}` - Successful execution with:
      * `result_state` - Updated state map (for state results)
      * `directives` - List of directives (for directive results)
      * `syscalls` - List of syscalls (for syscall results)
      * `status` - Set to :ok
      * `error` - Set to nil
    * `{:error, reason}` - Execution failed with:
      * String error for queue empty condition
      * Result struct with error details for execution failures

  ## Examples

      # Successful state update
      {:ok, %Result{result_state: %{status: :complete}}} =
        Runner.Simple.run(agent_with_state_update)

      # Successful directive
      {:ok, %Result{directives: [%EnqueueDirective{...}]}} =
        Runner.Simple.run(agent_with_directive)

      # Successful syscall
      {:ok, %Result{syscalls: [%SpawnSyscall{...}]}} =
        Runner.Simple.run(agent_with_syscall)

      # Empty queue error
      {:error, "No pending instructions"} =
        Runner.Simple.run(agent_with_empty_queue)

      # Execution error
      {:error, %Result{error: error, status: :error}} =
        Runner.Simple.run(agent_with_failing_action)

  ## Error Handling
    * Returns `{:error, "No pending instructions"}` for empty queue
    * Returns `{:error, %Result{}}` with error details for execution failures
    * All errors preserve the original agent state
    * Failed executions do not affect the remaining queue

  ## Logging
  Debug logs are emitted at key points:
    * Runner start with agent ID
    * Instruction dequeue result
    * Execution setup and workflow invocation
    * Result processing and categorization
  """
  @impl true
  @spec run(Jido.Agent.t(), run_opts()) :: run_result()
  def run(%{pending_instructions: instructions} = agent, _opts \\ []) do
    dbug("Starting simple runner execution",
      agent_id: agent.id,
      queue_size: :queue.len(instructions)
    )

    case :queue.out(instructions) do
      {{:value, %Instruction{} = instruction}, remaining} ->
        dbug("Dequeued instruction for execution",
          agent_id: agent.id,
          instruction: instruction,
          remaining_count: :queue.len(remaining)
        )

        execute_instruction(agent, instruction, remaining)

      {:empty, _} ->
        dbug("Execution skipped - empty instruction queue")

        result = %Result{
          initial_state: agent.state,
          instructions: [],
          result_state: agent.state,
          directives: [],
          syscalls: [],
          status: :ok
        }

        {:ok, result}
    end
  end

  @doc false
  @spec execute_instruction(Jido.Agent.t(), Instruction.t(), :queue.queue()) :: run_result()
  defp execute_instruction(agent, instruction, remaining) do
    dbug("Preparing execution context",
      agent_id: agent.id,
      action: instruction.action,
      params: instruction.params
    )

    # Initialize result tracking
    result = %Result{
      initial_state: agent.state,
      instructions: [instruction],
      pending_instructions: remaining
    }

    dbug("Executing workflow action",
      agent_id: agent.id,
      action: instruction.action
    )

    case Jido.Workflow.run(instruction.action, instruction.params, instruction.context) do
      {:ok, result_value} ->
        dbug("Workflow execution successful",
          agent_id: agent.id,
          result_type: get_result_type(result_value)
        )

        handle_successful_execution(result, result_value)

      {:error, error} ->
        dbug("Workflow execution failed",
          agent_id: agent.id,
          error: error,
          action: instruction.action
        )

        {:error, %{result | error: error, status: :error}}
    end
  end

  @doc false
  @spec handle_successful_execution(Result.t(), term()) :: {:ok, Result.t()}
  defp handle_successful_execution(result, result_value) do
    dbug("Processing execution result",
      result_type: get_result_type(result_value)
    )

    cond do
      Directive.is_directive?(result_value) ->
        dbug("Storing directive result")

        {:ok,
         %{
           result
           | result_state: result.initial_state,
             directives: [result_value],
             syscalls: [],
             status: :ok
         }}

      Syscall.is_syscall?(result_value) ->
        dbug("Storing syscall result")

        {:ok,
         %{
           result
           | result_state: result.initial_state,
             directives: [],
             syscalls: [result_value],
             status: :ok
         }}

      true ->
        dbug("Storing state result")
        {:ok, %{result | result_state: result_value, directives: [], syscalls: [], status: :ok}}
    end
  end
end
