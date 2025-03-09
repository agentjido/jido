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
  use ExDbug, enabled: false

  alias Jido.Instruction
  alias Jido.Error
  alias Jido.Agent.Directive

  @type run_opts :: [apply_directives?: boolean()]
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

      # Empty queue - returns agent unchanged
      {:ok, agent, []} = Runner.Simple.run(agent_with_empty_queue)

      # Execution error
      {:error, error} = Runner.Simple.run(agent_with_failing_action)

  ## Error Handling
    * Returns `{:error, "No pending instructions"}` for empty queue
    * Returns `{:error, error}` with error details for execution failures
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
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    dbug("Starting runner with agent", agent_id: agent.id)

    case :queue.out(instructions) do
      {{:value, %Instruction{} = instruction}, remaining} ->
        dbug("Dequeued instruction", instruction: instruction)
        agent = %{agent | pending_instructions: remaining}
        execute_instruction(agent, instruction, opts)

      {:empty, _} ->
        dbug("No pending instructions")
        {:ok, agent, []}
    end
  end

  @doc false
  @spec execute_instruction(Jido.Agent.t(), Instruction.t(), keyword()) :: run_result()
  defp execute_instruction(agent, instruction, opts) do
    # Inject agent state into instruction context
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}
    dbug("Executing instruction", instruction: instruction)

    case Jido.Workflow.run(instruction) do
      {:ok, result, directives} when is_list(directives) ->
        dbug("Workflow returned result with directive list",
          result: result,
          directives: directives
        )

        handle_directive_result(agent, result, directives, opts)

      {:ok, result, directive} ->
        dbug("Workflow returned result with single directive",
          result: result,
          directive: directive
        )

        handle_directive_result(agent, result, [directive], opts)

      {:ok, result} ->
        dbug("Workflow returned result only", result: result)
        {:ok, %{agent | result: result}, []}

      {:error, %Error{} = error} ->
        dbug("Workflow returned error struct", error: error)
        {:error, error}

      {:error, reason} when is_binary(reason) ->
        dbug("Workflow returned string error", reason: reason)
        handle_directive_error(reason)

      {:error, reason} ->
        dbug("Workflow returned other error", reason: reason)
        {:error, Error.new(:execution_error, "Workflow execution failed", reason)}
    end
  end

  @spec handle_directive_result(Jido.Agent.t(), term(), list(), keyword()) :: run_result()
  defp handle_directive_result(agent, result, directives, opts) do
    apply_directives? = Keyword.get(opts, :apply_directives?, true)
    dbug("Handling directive result", apply_directives?: apply_directives?)

    if apply_directives? do
      case Directive.apply_agent_directive(agent, directives) do
        {:ok, updated_agent, server_directives} ->
          dbug("Applied directives successfully", server_directives: server_directives)
          {:ok, %{updated_agent | result: result}, server_directives}

        {:error, %Error{} = error} ->
          dbug("Directive application failed with error struct", error: error)
          {:error, error}

        {:error, reason} ->
          dbug("Directive application failed with reason", reason: reason)
          {:error, Error.new(:validation_error, "Invalid directive", %{reason: reason})}
      end
    else
      dbug("Skipping directive application")
      {:ok, %{agent | result: result}, directives}
    end
  end

  @spec handle_directive_error(String.t()) :: {:error, Error.t()}
  defp handle_directive_error(reason) do
    dbug("Handling directive error", reason: reason)
    {:error, Error.validation_error("Invalid directive", %{reason: reason})}
  end
end
