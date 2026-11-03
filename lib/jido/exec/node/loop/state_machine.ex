defmodule Jido.Exec.Node.Loop.StateMachine do
  @moduledoc false

  alias Jido.Action.Validation
  alias Jido.Error
  alias Jido.Exec.{Frame, ValueResolver}
  alias Jido.Instruction

  @doc false
  @spec start(map(), term(), term()) :: {:ok, term(), map()} | {:error, term()}
  def start(%{kind: :reduce} = node, input, context) do
    with {:ok, frame} <- Frame.merge(input),
         state = Frame.resolver_state(frame, context),
         {:ok, collection} <- ValueResolver.resolve(node.collection, state),
         {:ok, items} <- enumerable(collection, node),
         {:ok, initial} <- ValueResolver.resolve(node.initial, state),
         :ok <- validate_reduce_initial(node, initial) do
      status = if items == [], do: :complete, else: :continue
      {:ok, {:jido_reduce, status, node.component, 0, initial}, %{frame: frame, items: items}}
    end
  end

  def start(%{kind: :iterate} = node, input, context) do
    with {:ok, frame} <- Frame.merge(input),
         resolver = Frame.resolver_state(frame, context),
         {:ok, initial} <- ValueResolver.resolve(node.state.initial, resolver),
         {:ok, initial} <- validate_iterate_state(node, initial, :initial, 0),
         {:ok, complete?} <- iterate_complete?(node, frame, initial, 0, nil, context) do
      status = if complete?, do: :complete, else: :continue
      {:ok, {:jido_iterate, status, node.component, initial, 0, nil}, %{frame: frame}}
    end
  end

  @doc false
  # Iteration values hold only loop progress. The frame and items ride in the
  # loop Fact meta, which is not part of Fact identity, so per-iteration cost
  # does not grow with the frame. Effects accumulate through the Fact meta.
  @spec run_action(map(), Instruction.t(), term(), map(), term(), function()) ::
          {:ok, term(), [term()]} | {:error, term()}
  def run_action(
        %{kind: :reduce} = node,
        instruction,
        {:jido_reduce, :continue, component, index, accumulator},
        %{frame: frame, items: items},
        context,
        action_runner
      ) do
    resolver =
      frame
      |> Frame.resolver_state(context)
      |> Map.merge(%{
        item: Enum.at(items, index),
        item_index: index,
        item_id: Frame.item_id(node.id, index),
        accumulator: accumulator
      })

    with {:ok, params} <- ValueResolver.resolve(node.call.params, resolver),
         {:ok, output, requests} <- action_runner.(instruction, params, context) do
      next_index = index + 1
      status = if next_index == length(items), do: :complete, else: :continue
      {:ok, {:jido_reduce, status, component, next_index, output}, requests}
    end
  end

  def run_action(
        %{kind: :iterate} = node,
        instruction,
        {:jido_iterate, :continue, component, state, completed, body_result},
        %{frame: frame},
        context,
        action_runner
      ) do
    resolver =
      frame
      |> Frame.resolver_state(context)
      |> Map.merge(%{
        iterate_state: state,
        iteration_index: completed,
        body_result: body_result
      })

    with {:ok, params} <- ValueResolver.resolve(node.call.params, resolver),
         {:ok, output, requests} <- action_runner.(instruction, params, context),
         {:ok, candidate} <-
           ValueResolver.resolve(node.state.update, Map.put(resolver, :body_result, output)),
         next_completed = completed + 1,
         {:ok, next_state} <-
           validate_iterate_state(node, candidate, :update, next_completed),
         {:ok, complete?} <-
           iterate_complete?(node, frame, next_state, next_completed, output, context),
         :ok <- within_iteration_limit(node, complete?, next_completed, next_state) do
      status = if complete?, do: :complete, else: :continue
      {:ok, {:jido_iterate, status, component, next_state, next_completed, output}, requests}
    end
  end

  defp iterable_error(node, value) do
    Error.execution_error("Reduce collection is not enumerable", %{
      node: node.component,
      phase: :reduce_collection,
      value: value,
      retry: false
    })
  end

  defp validate_reduce_initial(_node, value)
       when is_map(value) and not is_struct(value),
       do: :ok

  defp validate_reduce_initial(_node, %Jido.Action.Output{}), do: :ok

  defp validate_reduce_initial(node, value) do
    {:error,
     Error.execution_error("reduce initial value must be a map or Jido.Action.Output", %{
       node: node.component,
       phase: :reduce_initial,
       value: value,
       retry: false
     })}
  end

  defp enumerable(value, node) do
    if is_nil(Enumerable.impl_for(value)) do
      {:error, iterable_error(node, value)}
    else
      {:ok, Enum.to_list(value)}
    end
  end

  defp validate_iterate_state(node, value, phase, revision) do
    details = %{
      node: node.component,
      phase: if(phase == :initial, do: :iterate_state_initial, else: :iterate_state_update),
      state_revision: revision,
      retry: false
    }

    if is_map(value) and not is_struct(value) do
      case Validation.parse_preserving_shape(node.state.schema, value, details) do
        {:ok, validated} when is_map(validated) and not is_struct(validated) ->
          {:ok, validated}

        {:ok, validated} ->
          {:error,
           Error.execution_error(
             "iterator state schema must return a plain map",
             Map.merge(details, %{reason: :not_a_plain_map, value: validated})
           )}

        {:error, _reason} ->
          {:error, Error.validation_error("iterator state schema validation failed", details)}
      end
    else
      message =
        if phase == :initial,
          do: "iterator initial state must resolve to a plain map",
          else: "iterator state update must resolve to a plain map"

      {:error,
       Error.execution_error(
         message,
         Map.merge(details, %{reason: :not_a_plain_map, value: value})
       )}
    end
  end

  defp iterate_complete?(node, frame, state, completed, body_result, context) do
    resolver =
      frame
      |> Frame.resolver_state(context)
      |> Map.merge(%{
        iterate_state: state,
        iteration_index: completed,
        body_result: body_result
      })

    case ValueResolver.resolve(node.completion, resolver) do
      {:ok, value} when is_boolean(value) ->
        {:ok, value}

      {:ok, value} ->
        {:error,
         Error.execution_error("invalid iterator completion condition operands", %{
           phase: :iterate_completion,
           node: node.component,
           iterations: completed,
           reason: :invalid_boolean_operand,
           value: value,
           expression_path: [],
           retry: false
         })}

      {:error, error} ->
        {:error, put_loop_details(error, node, :iterate_completion, completed)}
    end
  end

  defp within_iteration_limit(_node, true, _completed, _state), do: :ok

  defp within_iteration_limit(node, false, completed, state)
       when completed >= node.max_iterations do
    {:error,
     Error.execution_error("flow iterator exhausted maximum iterations", %{
       phase: :iterate_exhaustion,
       node: node.component,
       max_iterations: node.max_iterations,
       completed_iterations: completed,
       state_revision: completed,
       state: state,
       retry: false
     })}
  end

  defp within_iteration_limit(_node, false, _completed, _state), do: :ok

  defp put_loop_details(%Error.ExecutionError{details: details} = error, node, phase, completed)
       when is_map(details) do
    %{
      error
      | phase: phase,
        details:
          Map.merge(details, %{
            node: node.component,
            iterations: completed,
            retry: false
          })
    }
  end

  defp put_loop_details(%{details: details} = error, node, phase, completed)
       when is_map(details) do
    %{
      error
      | details:
          Map.merge(details, %{
            phase: phase,
            node: node.component,
            iterations: completed,
            retry: false
          })
    }
  end

  defp put_loop_details(error, _node, _phase, _completed), do: error
end
