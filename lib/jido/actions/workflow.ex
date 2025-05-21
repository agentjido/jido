defmodule Jido.Actions.Workflow do
  @moduledoc """
  A specialized Action type that executes a sequence of workflow steps.

  This Workflow is intentinoally simplistic - it is not meant to replace more mature Workflow
  libraries that exist in the Elixir ecosystem.  It is included for basic use cases relevant to
  the Jido project.

  This module extends `Jido.Action` with workflow capabilities, allowing
  you to define a sequence of steps to be executed in order. Each step
  follows the Elixir AST pattern of `{:atom, metadata, params}`.

  ## Supported Step Types

  - `{:step, metadata, [instruction]}` - Execute a single instruction
  - `{:branch, metadata, [condition_value, true_action, false_action]}` - Conditional branching
  - `{:converge, metadata, [instruction]}` - Converge branch paths
  - `{:parallel, metadata, [instructions]}` - Execute instructions in parallel

  ## Usage

  ```elixir
  defmodule MyWorkflow do
    use Jido.Actions.Workflow,
      name: "my_workflow",
      description: "A workflow that performs multiple steps",
      steps: [
        {:step, [name: "step_1"], [{LogAction, message: "Step 1"}]},
        {:branch, [name: "branch_1"], [
          true,  # This will typically be replaced at runtime with a dynamic value
          {:step, [name: "true_branch"], [{LogAction, message: "Greater than 10"}]},
          {:step, [name: "false_branch"], [{LogAction, message: "Less than or equal to 10"}]}
        ]},
        {:step, [name: "final_step"], [{LogAction, message: "Completed"}]}
      ]
  end
  ```

  ## Handling Dynamic Conditions

  For branch conditions that need to be evaluated at runtime, override the `execute_step/3`
  function in your module to handle the specific branch condition check:

  ```elixir
  # Override execute_step to handle a specific branch condition
  def execute_step({:branch, [name: "my_condition"], [_placeholder, true_branch, false_branch]}, params, context) do
    # Determine condition dynamically using params
    condition_value = params.value > 10

    # Choose the branch based on the condition value
    if condition_value do
      execute_step(true_branch, params, context)
    else
      execute_step(false_branch, params, context)
    end
  end

  # Fall back to the default implementation for other steps
  def execute_step(step, params, context) do
    super(step, params, context)
  end
  """

  alias Jido.Error
  alias Jido.Instruction

  # Valid step types
  @valid_step_types [:step, :branch, :converge, :parallel]

  # Custom validation function for workflow steps
  @doc false
  def validate_step(steps) when is_list(steps) do
    # Simple validation to check that steps are tuples with the right format
    valid_steps =
      Enum.all?(steps, fn
        {step_type, metadata, _params} when is_atom(step_type) and is_list(metadata) ->
          step_type in @valid_step_types

        _ ->
          false
      end)

    if valid_steps, do: {:ok, steps}, else: {:error, "invalid workflow steps format"}
  end

  def validate_step(_), do: {:error, "steps must be a list of tuples"}

  # Schema for validating workflow configuration
  @workflow_config_schema NimbleOptions.new!(
                            workflow: [
                              type: {:custom, __MODULE__, :validate_step, []},
                              required: true,
                              doc: """
                              List of workflow steps to execute. Each step follows the Elixir AST pattern
                              of `{:atom, metadata, params}`. Supported step types:

                              - `:step` - Execute a single instruction
                              - `:branch` - Conditional branching based on a boolean value
                              - `:converge` - Converge branch paths
                              - `:parallel` - Execute instructions in parallel
                              """
                            ]
                          )

  # Define the callback for step execution
  @callback execute_step(step :: tuple(), params :: map(), context :: map()) ::
              {:ok, map()} | {:error, any()}

  # Make the callback optional
  @optional_callbacks [execute_step: 3]

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@workflow_config_schema)
    valid_step_types = @valid_step_types

    quote location: :keep do
      # Separate WorkflowAction-specific options from base Action options
      workflow_keys = [:workflow]
      workflow_opts = Keyword.take(unquote(opts), workflow_keys)
      action_opts = Keyword.drop(unquote(opts), workflow_keys)

      # Store valid step types
      @valid_step_types unquote(valid_step_types)

      # Validate WorkflowAction-specific options
      case NimbleOptions.validate(workflow_opts, unquote(escaped_schema)) do
        {:ok, validated_workflow_opts} ->
          # Store validated workflow options for later use - steps will be stored as module attribute
          @workflow_steps validated_workflow_opts[:workflow]

          # Add workflow flag
          @workflow true

          # Pass the remaining options to the base Action
          use Jido.Action, action_opts

          # Implement the behavior
          @behaviour Jido.Actions.Workflow

          # Implement the run function that executes the workflow
          @impl Jido.Action
          def run(params, context) do
            # Execute the workflow steps sequentially
            execute_workflow(@workflow_steps, params, context)
          end

          # Add workflow-specific functionality
          def workflow?, do: @workflow
          def workflow_steps, do: @workflow_steps

          # Make to_json overridable before redefining it
          defoverridable to_json: 0

          # Override to_json to include workflow flag and steps
          def to_json do
            # Get the base JSON from Jido.Action
            base_json = super()
            # Add workflow flag and steps to the result
            base_json
            |> Map.put(:workflow, @workflow)
            |> Map.put(:steps, @workflow_steps)
          end

          # Make to_tool overridable before redefining it
          defoverridable to_tool: 0

          # Override to_tool to ensure the output format matches expectations
          def to_tool do
            tool = super()

            # Map keys can be atoms or strings, standardize on strings
            # Also rename parameters_schema to parameters for compatibility
            tool
            |> Map.new(fn
              {k, v} when is_atom(k) -> {Atom.to_string(k), v}
              entry -> entry
            end)
            |> Map.put("parameters", Map.get(tool, "parameters_schema", %{}))
          end

          # Helper function to execute the workflow steps
          defp execute_workflow(steps, params, context) do
            # This will hold the accumulated results and updated params as we go
            initial_acc = {:ok, params, %{}}

            # Fold over the steps, executing each one and accumulating results
            Enum.reduce_while(steps, initial_acc, fn step, {_status, current_params, results} ->
              case execute_step(step, current_params, context) do
                {:ok, step_result} ->
                  # Merge the step result into results and update params for next step
                  updated_results = Map.merge(results, step_result)
                  updated_params = Map.merge(current_params, step_result)
                  {:cont, {:ok, updated_params, updated_results}}

                {:error, reason} ->
                  # Stop execution on error
                  {:halt, {:error, reason}}
              end
            end)
            |> case do
              {:ok, _final_params, final_results} -> {:ok, final_results}
              {:error, reason} -> {:error, reason}
            end
          end

          # Default implementation for execute_step
          def execute_step(step, params, context) do
            case step do
              {:step, _metadata, [instruction]} ->
                # Execute a single instruction
                execute_instruction(instruction, params, context)

              {:branch, metadata, [condition, true_branch, false_branch]} ->
                # Evaluate the condition and take the appropriate branch
                execute_branch(condition, true_branch, false_branch, params, context, metadata)

              {:converge, _metadata, [instruction]} ->
                # Execute a convergence point
                execute_instruction(instruction, params, context)

              {:parallel, _metadata, instructions} ->
                # Execute instructions in parallel
                execute_parallel(instructions, params, context)

              _ ->
                {:error, %{type: :invalid_step, message: "Unknown step type: #{inspect(step)}"}}
            end
          end

          # Helper function to execute a single instruction
          defp execute_instruction(instruction, params, context) do
            # Normalize the instruction to a Jido.Instruction struct
            {:ok, normalized} = Instruction.normalize_single(instruction)

            if not is_struct(normalized, Jido.Instruction) do
              # Handle unexpected return from normalize
              {:error,
               %{
                 type: :invalid_instruction,
                 message: "Failed to normalize instruction: #{inspect(instruction)}"
               }}
            else
              # Extract the action module
              action = normalized.action

              # Merge instruction params with current params
              merged_params = Map.merge(params, normalized.params)

              # Execute the action
              case action.run(merged_params, context) do
                {:ok, result} ->
                  {:ok, result}

                {:error, reason} ->
                  {:error, reason}

                other ->
                  # Handle unexpected return values
                  {:error,
                   %{
                     type: :invalid_result,
                     message: "Action returned unexpected value: #{inspect(other)}"
                   }}
              end
            end
          end

          # Helper function to execute a branch - simpler version that works with static conditions
          defp execute_branch(condition, true_branch, false_branch, params, context, metadata)
               when is_boolean(condition) do
            if condition do
              execute_step(true_branch, params, context)
            else
              execute_step(false_branch, params, context)
            end
          end

          # Default branch implementation for conditions we don't specifically handle
          defp execute_branch(
                 _condition,
                 _true_branch,
                 _false_branch,
                 _params,
                 _context,
                 metadata
               ) do
            {:error,
             %{
               type: :invalid_condition,
               message: "Invalid or unhandled condition in branch #{inspect(metadata)}"
             }}
          end

          # Helper function to execute steps in parallel
          defp execute_parallel(instructions, params, context) do
            # Placeholder implementation - in a real implementation,
            # this would execute the instructions concurrently
            results =
              Enum.map(instructions, fn instruction ->
                case execute_step(instruction, params, context) do
                  {:ok, result} -> result
                  {:error, reason} -> %{error: reason}
                end
              end)

            {:ok, %{parallel_results: results}}
          end

          # Allow execute_step to be overridden
          defoverridable execute_step: 3

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "WorkflowAction", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end
end
