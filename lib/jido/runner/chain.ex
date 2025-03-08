defmodule Jido.Runner.Chain do
  @moduledoc """
  A runner that executes instructions sequentially with support for result chaining.

  ## Chain Execution
  Instructions are executed in sequence with the output of each instruction
  becoming the input for the next instruction in the chain via the merge_results option.

  ## Features
  * Sequential instruction execution
  * Result chaining between instructions
  * Directive accumulation
  * Comprehensive error handling
  """
  @behaviour Jido.Runner

  alias Jido.Instruction
  alias Jido.Agent.Directive
  alias Jido.Error

  @type chain_result :: {:ok, Jido.Agent.t(), [Directive.t()]} | {:error, Error.t()}
  @type chain_opts :: [
    merge_results: boolean(),
    apply_directives?: boolean()
  ]

  @doc """
  Executes a chain of instructions sequentially, with optional result merging.

  ## Parameters
    * `agent` - The agent struct containing:
      * `pending_instructions` - Queue of pending instructions
      * `state` - Current agent state
      * `id` - Agent identifier
    * `opts` - Optional keyword list of execution options:
      * `:merge_results` - When true, merges each result into the next instruction's params (default: true)
      * `:apply_directives?` - When true (default), applies directives during execution

  ## Returns
    * `{:ok, updated_agent, directives}` - Chain completed successfully with:
      * Final result stored in agent.result
      * List of accumulated directives
    * `{:error, error}` - Chain execution failed with error details

  ## Examples

      # Basic chain execution
      {:ok, updated_agent, directives} = Chain.run(agent)

      # Chain with result merging disabled
      {:ok, updated_agent, directives} = Chain.run(agent, merge_results: false)

      # Chain without applying directives
      {:ok, updated_agent, directives} = Chain.run(agent, apply_directives?: false)
  """
  @impl true
  @spec run(Jido.Agent.t(), chain_opts()) :: chain_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    case :queue.to_list(instructions) do
      [] ->
        {:ok, %{agent | pending_instructions: :queue.new()}, []}

      instructions_list ->
        execute_chain(agent, instructions_list, opts)
    end
  end

  @spec execute_chain(Jido.Agent.t(), [Instruction.t()], keyword()) :: chain_result()
  defp execute_chain(agent, instructions_list, opts) do
    merge_results = Keyword.get(opts, :merge_results, true)
    agent = %{agent | pending_instructions: :queue.new()}
    execute_chain_step(instructions_list, agent, [], %{}, merge_results, opts)
  end

  @spec execute_chain_step([Instruction.t()], Jido.Agent.t(), [Directive.t()], map(), boolean(), keyword()) ::
          chain_result()
  defp execute_chain_step([], agent, accumulated_directives, last_result, _merge_results, opts) do
    apply_directives? = Keyword.get(opts, :apply_directives?, true)

    if apply_directives? do
      case Directive.apply_agent_directive(agent, accumulated_directives) do
        {:ok, updated_agent, server_directives} ->
          {:ok, %{updated_agent | result: last_result}, server_directives}

        {:error, %Error{} = error} ->
          {:error, error}

        {:error, reason} ->
          {:error, Error.new(:validation_error, "Invalid directive", %{reason: reason})}
      end
    else
      {:ok, %{agent | result: last_result}, accumulated_directives}
    end
  end

  defp execute_chain_step(
         [instruction | remaining],
         agent,
         accumulated_directives,
         last_result,
         merge_results,
         opts
       ) do
    # Merge last_result into instruction params if enabled
    instruction =
      if merge_results do
        %{instruction | params: Map.merge(instruction.params, last_result)}
      else
        instruction
      end

    # Inject agent state into instruction context
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

    case Jido.Workflow.run(instruction) do
      {:ok, result, directives} when is_list(directives) ->
        handle_chain_result(
          result,
          directives,
          remaining,
          agent,
          accumulated_directives,
          merge_results,
          opts
        )

      {:ok, result, directive} ->
        handle_chain_result(
          result,
          [directive],
          remaining,
          agent,
          accumulated_directives,
          merge_results,
          opts
        )

      {:ok, result} ->
        execute_chain_step(remaining, agent, accumulated_directives, result, merge_results, opts)

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} when is_binary(reason) ->
        {:error, Error.validation_error("Invalid directive", %{reason: reason})}

      {:error, reason} ->
        {:error, Error.new(:execution_error, "Chain execution failed", reason)}
    end
  end

  @spec handle_chain_result(
          term(),
          [Directive.t() | Instruction.t()],
          [Instruction.t()],
          Jido.Agent.t(),
          [Directive.t()],
          boolean(),
          keyword()
        ) ::
          chain_result()
  defp handle_chain_result(
         result,
         directives,
         remaining,
         agent,
         accumulated_directives,
         merge_results,
         opts
       ) do
    # Convert any instructions to enqueue directives
    processed_directives =
      Enum.map(directives, fn
        %Instruction{} = instruction -> Directive.Enqueue.new(instruction)
        directive -> directive
      end)

    updated_directives = accumulated_directives ++ processed_directives
    execute_chain_step(remaining, agent, updated_directives, result, merge_results, opts)
  end
end
