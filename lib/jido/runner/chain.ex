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
  use ExDbug, enabled: false
  alias Jido.Instruction
  alias Jido.Agent.Directive
  alias Jido.Error

  @type chain_result :: {:ok, Jido.Agent.t(), [Directive.t()]} | {:error, Error.t()}
  @type chain_opts :: [
          merge_results: boolean(),
          apply_directives?: boolean(),
          log_level: atom(),
          timeout: non_neg_integer()
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
      * `:timeout` - Timeout in milliseconds for action execution (merged with instruction opts)
      * `:log_level` - Log level for debugging output

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

      # Chain with custom timeout (runner opts are merged with instruction opts)
      {:ok, updated_agent, directives} = Chain.run(agent, timeout: 60_000)
  """
  @impl true
  @spec run(Jido.Agent.t(), chain_opts()) :: chain_result()
  def run(%{pending_instructions: instructions} = agent, opts \\ []) do
    dbug("Starting chain run", agent: agent.id, opts: opts)

    case :queue.to_list(instructions) do
      [] ->
        dbug("No instructions to run", agent: agent.id)
        {:ok, %{agent | pending_instructions: :queue.new()}, []}

      instructions_list ->
        dbug("Executing chain", agent: agent.id, instructions: length(instructions_list))
        execute_chain(agent, instructions_list, opts)
    end
  end

  @spec execute_chain(Jido.Agent.t(), [Instruction.t()], keyword()) :: chain_result()
  defp execute_chain(agent, instructions_list, opts) do
    dbug("Setting up chain execution", agent: agent.id)
    merge_results = Keyword.get(opts, :merge_results, true)
    agent = %{agent | pending_instructions: :queue.new()}
    execute_chain_step(instructions_list, agent, [], %{}, merge_results, opts)
  end

  @spec execute_chain_step(
          [Instruction.t()],
          Jido.Agent.t(),
          [Directive.t()],
          map(),
          boolean(),
          keyword()
        ) ::
          chain_result()
  defp execute_chain_step([], agent, accumulated_directives, last_result, _merge_results, opts) do
    dbug("Chain execution complete", agent: agent.id, directives: length(accumulated_directives))
    apply_directives? = Keyword.get(opts, :apply_directives?, true)

    if apply_directives? do
      dbug("Applying accumulated directives", agent: agent.id)

      case Directive.apply_agent_directive(agent, accumulated_directives) do
        {:ok, updated_agent, server_directives} ->
          dbug("Directives applied successfully", agent: agent.id)
          {:ok, %{updated_agent | result: last_result}, server_directives}

        {:error, %Error{} = error} ->
          dbug("Error applying directives", agent: agent.id, error: error)
          {:error, error}

        {:error, reason} ->
          dbug("Error applying directives", agent: agent.id, reason: reason)
          {:error, Error.new(:validation_error, "Invalid directive", %{reason: reason})}
      end
    else
      dbug("Skipping directive application", agent: agent.id)
      {:ok, %{agent | result: last_result}, accumulated_directives}
    end
  end

  @dialyzer {:nowarn_function, execute_chain_step: 6}
  # This function correctly handles 3-tuple returns from Jido.Exec.run/1 but Dialyzer
  # incorrectly reports them as unreachable due to conservative type inference
  defp execute_chain_step(
         [instruction | remaining],
         agent,
         accumulated_directives,
         last_result,
         merge_results,
         opts
       ) do
    dbug("Executing chain step", agent: agent.id, instruction: instruction.id)
    # Merge last_result into instruction params if enabled
    instruction =
      if merge_results do
        dbug("Merging results into params", agent: agent.id)
        %{instruction | params: Map.merge(instruction.params, last_result)}
      else
        instruction
      end

    # Inject agent state and merge opts with instruction opts
    # Instruction opts take precedence over runner opts
    merged_opts = Keyword.merge(opts, instruction.opts)

    instruction = %{
      instruction
      | context: Map.put(instruction.context, :state, agent.state),
        opts: merged_opts
    }

    dbug("Running action", agent: agent.id, instruction: instruction.id)

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        dbug("Exec returned result with no directives", agent: agent.id)
        execute_chain_step(remaining, agent, accumulated_directives, result, merge_results, opts)

      {:ok, result, directives} when is_list(directives) ->
        dbug("Exec returned result with directive list", agent: agent.id)

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
        dbug("Exec returned result with single directive", agent: agent.id)

        handle_chain_result(
          result,
          [directive],
          remaining,
          agent,
          accumulated_directives,
          merge_results,
          opts
        )

      {:error, %Error{} = error} ->
        dbug("Exec returned error", agent: agent.id, error: error)
        {:error, error}

      {:error, reason} when is_binary(reason) ->
        dbug("Exec returned string error", agent: agent.id, reason: reason)
        {:error, Error.validation_error("Invalid directive", %{reason: reason})}

      {:error, reason} ->
        dbug("Exec returned generic error", agent: agent.id, reason: reason)
        {:error, Error.new(:execution_error, "Chain execution failed", reason)}
    end
  end

  @dialyzer {:nowarn_function, handle_chain_result: 7}
  # This function is called from execute_chain_step/6 but Dialyzer incorrectly reports it as unused
  # due to conservative type inference on 3-tuple returns from Jido.Exec.run/1
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
    dbug("Handling chain result", agent: agent.id, directives: length(directives))
    # Convert any instructions to enqueue directives
    processed_directives =
      Enum.map(directives, fn
        %Instruction{} = instruction -> Directive.Enqueue.new(instruction)
        directive -> directive
      end)

    updated_directives = accumulated_directives ++ processed_directives
    dbug("Continuing chain execution", agent: agent.id, remaining: length(remaining))
    execute_chain_step(remaining, agent, updated_directives, result, merge_results, opts)
  end
end
