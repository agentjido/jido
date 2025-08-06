defmodule Jido.Actions.Iterator do
  @moduledoc """
  An advanced iterator action that demonstrates Chain of Thought behavior by executing
  a body action at each iteration step and using a decision action to determine whether
  to continue iterating. This provides a flexible framework for complex iterative workflows.
  
  The iterator maintains state between iterations and can execute arbitrary actions
  as the "body" of each iteration, while a separate "decision" action controls flow.
  """

  use Jido.Action,
    name: "iterator",
    description: "Iterates by executing body action and using decision action to control flow",
    schema: [
      run_id: [type: :string, doc: "Unique identifier for this iteration sequence"],
      step: [type: :integer, default: 0, doc: "Current step number"],
      max_steps: [type: :integer, default: 10, doc: "Maximum number of steps (safety limit)"],
      body_action: [type: :atom, required: true, doc: "Action to execute on each iteration"],
      body_params: [type: :map, default: %{}, doc: "Parameters for the body action"],
      decision_action: [type: :atom, doc: "Action to determine whether to continue (optional)"],
      decision_params: [type: :map, default: %{}, doc: "Parameters for the decision action"],
      state_path: [type: {:list, :atom}, default: [:iterator_state], doc: "Path in agent state to store iteration state"]
    ]

  alias Jido.Agent.Directive.StateModification
  alias Jido.Util

  @impl true
  def run(params, context) do
    run_id = params[:run_id] || Util.generate_id()
    step = params[:step] || 0
    max_steps = params[:max_steps] || 10
    body_action = params[:body_action]
    body_params = params[:body_params] || %{}
    decision_action = params[:decision_action]
    decision_params = params[:decision_params] || %{}
    state_path = params[:state_path] || [:iterator_state]
    
    # Get current iteration state from agent state
    state = get_in(context.state, state_path ++ [run_id]) || %{}

    # Safety check: prevent infinite loops
    if step >= max_steps do
      result = %{
        run_id: run_id,
        step: step,
        max_steps: max_steps,
        state: state,
        completed: true,
        termination_reason: :max_steps_reached,
        message: "Iterator terminated: maximum steps (#{max_steps}) reached"
      }
      
      # Clean up state when iteration completes
      cleanup_directive = %StateModification{
        op: :delete,
        path: state_path ++ [run_id],
        value: nil
      }
      
      {:ok, result, cleanup_directive}
    else
      # Execute the body action with current state
      body_params_with_state = Map.merge(body_params, %{
        step: step,
        run_id: run_id,
        iterator_state: state
      })

      case execute_action(body_action, body_params_with_state, context) do
        {:ok, body_result} ->
          # Update state with body result - merge the body result into the state
          updated_state = Map.merge(state, body_result)
          updated_state = Map.merge(updated_state, %{
            last_step_result: body_result,
            steps_completed: (state[:steps_completed] || []) ++ [step]
          })

          # Determine if we should continue iterating
          should_continue = should_continue_iteration?(
            decision_action,
            decision_params,
            updated_state,
            step,
            max_steps,
            context
          )

          result = %{
            run_id: run_id,
            step: step,
            max_steps: max_steps,
            state: updated_state,
            body_result: body_result,
            completed: not should_continue,
            message: "Step #{step} completed"
          }

          if should_continue do
            # Ensure path exists and create directives to store state and enqueue next iteration
            path_directives = ensure_path_exists(state_path ++ [run_id], context.state)
            state_directive = %StateModification{
              op: :set,
              path: state_path ++ [run_id],
              value: updated_state
            }
            
            next_params = %{
              run_id: run_id,
              step: step + 1,
              max_steps: max_steps,
              body_action: body_action,
              body_params: body_params,
              decision_action: decision_action,
              decision_params: decision_params,
              state_path: state_path
            }

            enqueue_directive = %Jido.Agent.Directive.Enqueue{
              action: Jido.Actions.Iterator,
              params: next_params,
              context: %{}
            }

            {:ok, result, path_directives ++ [state_directive, enqueue_directive]}
          else
            # Iteration complete - clean up state
            result = Map.merge(result, %{
              completed: true,
              termination_reason: :decision_action_stopped,
              message: "Iterator completed after #{step + 1} steps"
            })
            
            cleanup_directive = %StateModification{
              op: :delete,
              path: state_path ++ [run_id],
              value: nil
            }
            
            {:ok, result, cleanup_directive}
          end

        {:error, error} ->
          result = %{
            run_id: run_id,
            step: step,
            max_steps: max_steps,
            state: state,
            completed: true,
            termination_reason: :body_action_error,
            error: error,
            message: "Iterator terminated due to body action error at step #{step}"
          }
          
          # Clean up state on error
          cleanup_directive = %StateModification{
            op: :delete,
            path: state_path ++ [run_id],
            value: nil
          }
          
          {:ok, result, cleanup_directive}
      end
    end
  end

  # Execute an action with error handling
  defp execute_action(action_module, params, context) do
    try do
      case action_module.run(params, context) do
        {:ok, result} -> {:ok, result}
        {:ok, result, _directive} -> {:ok, result}  # Ignore directives from body actions
        {:error, error} -> {:error, error}
        other -> {:error, "Invalid action return: #{inspect(other)}"}
      end
    rescue
      error -> {:error, "Action execution failed: #{inspect(error)}"}
    catch
      error -> {:error, "Action execution caught: #{inspect(error)}"}
    end
  end

  # Determine whether to continue iteration
  defp should_continue_iteration?(nil, _decision_params, _state, step, max_steps, _context) do
    # No decision action provided, use simple step limit
    step + 1 < max_steps
  end

  defp should_continue_iteration?(decision_action, decision_params, state, step, max_steps, context) do
    # Execute decision action to determine if we should continue
    decision_params_with_state = Map.merge(decision_params, %{
      step: step,
      max_steps: max_steps,
      iterator_state: state
    })

    case execute_action(decision_action, decision_params_with_state, context) do
      {:ok, %{continue: continue}} when is_boolean(continue) -> 
        continue and step + 1 < max_steps
      {:ok, result} when is_map(result) -> 
        # Look for various continue indicators
        continue = result[:continue] || result["continue"] || 
                  result[:should_continue] || result["should_continue"] ||
                  false
        continue and step + 1 < max_steps
      {:error, _error} -> 
        # Decision action failed, stop iteration
        false
      _other -> 
        # Invalid decision result, stop iteration
        false
    end
  end

  # Ensure that all intermediate paths exist in the state
  defp ensure_path_exists(path, state) do
    path
    |> Enum.reduce({[], []}, fn key, {current_path, directives} ->
      current_path = current_path ++ [key]

      if length(current_path) < length(path) and get_in(state, current_path) == nil do
        {current_path,
         directives ++
           [
             %StateModification{
               op: :set,
               path: current_path,
               value: %{}
             }
           ]}
      else
        {current_path, directives}
      end
    end)
    |> elem(1)
  end
end
