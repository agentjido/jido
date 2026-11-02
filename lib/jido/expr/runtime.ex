defmodule Jido.Expr.Runtime do
  @moduledoc false

  alias Jido.Expr
  alias Jido.Expr.Limits

  @doc false
  @spec evaluate(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def evaluate(value, options) do
    with {:ok, state} <- Limits.new(options, [:resolve]),
         :ok <- expression_root(value),
         {:ok, result, _state} <- visit(value, state, [], 0, :evaluate) do
      {:ok, result}
    end
  end

  @doc false
  @spec validate(term(), keyword()) :: :ok | {:error, term()}
  def validate(value, options) do
    with {:ok, state} <- Limits.new(options, [:validate_leaf]),
         :ok <- expression_root(value),
         {:ok, _value, _state} <- visit(value, state, [], 0, :validate) do
      :ok
    end
  end

  # Ingress normalization uses the same bounded walk as validation. The host
  # can replace a legacy struct with Expr or normalize a reference. It cannot
  # install operators or run an operation during this walk.
  @doc false
  @spec normalize(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def normalize(value, options) do
    with {:ok, state} <- Limits.new(options, [:normalize_leaf, :validate_leaf]),
         {:ok, value, _state} <- visit(value, state, [], 0, :normalize) do
      {:ok, value}
    end
  end

  @doc false
  @spec reduce(term(), term(), function(), keyword()) :: {:ok, term()} | {:error, term()}
  def reduce(value, accumulator, reducer, options) do
    if is_function(reducer, 2) or is_function(reducer, 3) do
      with {:ok, state} <- Limits.new(options, []) do
        state = Map.merge(state, %{accumulator: accumulator, reducer: reducer})

        case visit(value, state, [], 0, :reduce) do
          {:ok, _value, state} -> {:ok, state.accumulator}
          {:halt, state} -> {:ok, state.accumulator}
          {:error, _error} = error -> error
        end
      end
    else
      Limits.fail(:invalid_reducer, [])
    end
  end

  defp reduce_callback(reducer, value, path, accumulator) do
    result =
      if is_function(reducer, 3),
        do: reducer.(value, path, accumulator),
        else: reducer.(value, accumulator)

    {:ok, result}
  rescue
    _ -> Limits.fail(:reducer_failure, path)
  catch
    _, _ -> Limits.fail(:reducer_failure, path)
  end

  defp expression_root(%Expr{}), do: :ok
  defp expression_root(_value), do: Limits.fail(:expected_expression, [])

  defp visit(value, state, path, depth, :reduce) do
    with {:ok, state} <- Limits.enter(state, value, path, depth),
         {:ok, directive} <-
           reduce_callback(state.reducer, value, path, state.accumulator) do
      case directive do
        {:cont, accumulator} ->
          visit_value(value, %{state | accumulator: accumulator}, path, depth, :reduce)

        {:halt, accumulator} ->
          {:halt, %{state | accumulator: accumulator}}

        {:error, error} ->
          {:error, error}

        _other ->
          Limits.fail(:invalid_reducer_return, path)
      end
    end
  end

  defp visit(value, state, path, depth, mode) do
    with {:ok, value} <- normalize_value(value, state, path, depth, mode),
         {:ok, state} <- Limits.enter(state, value, path, depth) do
      visit_value(value, state, path, depth, mode)
    end
  end

  defp normalize_value(%Expr{} = value, _state, _path, _depth, _mode), do: {:ok, value}

  defp normalize_value(%_{} = value, %{normalize_leaf: callback} = state, path, depth, :normalize) do
    with {:ok, _state} <- Limits.enter(state, value, path, depth) do
      case Limits.callback(callback, value, path) do
        {:ok, value} -> {:ok, value}
        {:error, error} -> Limits.callback_error(error, path)
        _ -> Limits.fail(:invalid_callback_return, path)
      end
    end
  end

  defp normalize_value(value, _state, _path, _depth, _mode), do: {:ok, value}

  defp visit_value(value, state, path, depth, :data) when is_map(value),
    do: map(:maps.iterator(value), state, path, depth, :data, value)

  defp visit_value(value, state, path, depth, :data) when is_list(value),
    do: list(value, state, path, depth, :data, 0, value)

  defp visit_value(value, state, path, depth, :data) when is_tuple(value),
    do: tuple(value, state, path, depth, 0)

  defp visit_value(value, state, _path, _depth, :data), do: {:ok, value, state}

  defp visit_value(%Expr{} = expression, state, path, depth, mode) do
    with :ok <- shape(expression, state, path) do
      expression(expression, state, path, depth, mode)
    end
  end

  defp visit_value(%_{} = value, state, _path, _depth, :reduce),
    do: {:ok, value, state}

  defp visit_value(%_{} = value, state, path, depth, mode),
    do: host(value, state, path, depth, mode)

  defp visit_value(value, state, path, depth, :validate) when is_map(value),
    do: map(:maps.iterator(value), state, path, depth, :validate, value)

  defp visit_value(value, state, path, depth, mode) when is_map(value),
    do: map(:maps.iterator(value), state, path, depth, mode, %{})

  defp visit_value(value, state, path, depth, :validate) when is_list(value),
    do: list(value, state, path, depth, :validate, 0, value)

  defp visit_value(value, state, path, depth, mode) when is_list(value),
    do: list(value, state, path, depth, mode, 0, [])

  defp visit_value(value, state, _path, _depth, _mode)
       when is_atom(value) or is_number(value) or is_binary(value),
       do: {:ok, value, state}

  defp visit_value(value, _state, path, _depth, _mode),
    do: Limits.fail(:unsupported_value, path, nil, %{type: Limits.type(value)})

  defp map(iterator, state, path, depth, mode, result) do
    case :maps.next(iterator) do
      :none ->
        {:ok, result, state}

      {key, child, iterator} ->
        with {:ok, child, state} <- map_pair(key, child, state, path, depth, mode) do
          result = map_result(mode, result, key, child)
          map(iterator, state, path, depth, mode, result)
        end
    end
  end

  defp map_result(mode, result, _key, _child) when mode in [:data, :reduce, :validate],
    do: result

  defp map_result(_mode, result, key, child), do: Map.put(result, key, child)

  defp map_pair(key, value, state, path, depth, :data) do
    with {:ok, _key, state} <- visit(key, state, path, depth + 1, :data) do
      visit(value, state, path, depth + 1, :data)
    end
  end

  defp map_pair(key, value, state, path, depth, mode)
       when is_atom(key) or is_binary(key) or is_integer(key) do
    child_path = path ++ [key]

    with {:ok, _key, state} <- visit(key, state, child_path, depth + 1, :data) do
      visit(value, state, child_path, depth + 1, mode)
    end
  end

  defp map_pair(key, _value, _state, path, _depth, _mode),
    do: Limits.fail(:invalid_map_key, path, nil, %{type: Limits.type(key)})

  defp tuple(value, state, _path, _depth, index) when index == tuple_size(value),
    do: {:ok, value, state}

  defp tuple(value, state, path, depth, index) do
    with {:ok, _child, state} <-
           visit(elem(value, index), state, path ++ [index], depth + 1, :data) do
      tuple(value, state, path, depth, index + 1)
    end
  end

  defp list([], state, _path, _depth, mode, _index, result)
       when mode in [:data, :reduce, :validate],
       do: {:ok, result, state}

  defp list([], state, _path, _depth, _mode, _index, result),
    do: {:ok, Enum.reverse(result), state}

  defp list([head | tail], state, path, depth, mode, index, result)
       when mode in [:data, :reduce, :validate] do
    with {:ok, _value, state} <- visit(head, state, path ++ [index], depth + 1, mode) do
      list(tail, state, path, depth, mode, index + 1, result)
    end
  end

  defp list([head | tail], state, path, depth, mode, index, result) do
    with {:ok, value, state} <- visit(head, state, path ++ [index], depth + 1, mode) do
      list(tail, state, path, depth, mode, index + 1, [value | result])
    end
  end

  defp list(tail, state, path, depth, :data, index, result) do
    with {:ok, _tail, state} <- visit(tail, state, path ++ [index], depth + 1, :data) do
      {:ok, result, state}
    end
  end

  defp list(_tail, _state, path, _depth, _mode, index, _result),
    do: Limits.fail(:improper_list, path ++ [index])

  defp shape(%Expr{operator: operator, operands: operands}, _state, path) do
    case Expr.new(operator, operands) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, %{error | path: path}}
    end
  end

  defp expression(%Expr{operands: operands} = value, state, path, depth, mode)
       when mode in [:reduce, :validate] do
    with {:ok, _operands, state} <-
           list(operands, state, path ++ [:operands], depth, mode, 0, operands) do
      {:ok, value, state}
    end
  end

  defp expression(%Expr{operands: operands} = value, state, path, depth, :normalize) do
    with {:ok, operands, state} <-
           list(operands, state, path ++ [:operands], depth, :normalize, 0, []) do
      {:ok, %{value | operands: operands}, state}
    end
  end

  defp expression(
         %Expr{operator: operator, operands: [left, right]},
         state,
         path,
         depth,
         :evaluate
       )
       when operator in [:and, :or] do
    left_path = path ++ [:operands, 0]

    with {:ok, value, state} <- visit(left, state, left_path, depth + 1, :evaluate) do
      binary_boolean(operator, value, right, state, left_path, path, depth)
    end
  end

  defp expression(%Expr{operator: operator, operands: operands}, state, path, depth, :evaluate) do
    with {:ok, values, state} <-
           list(operands, state, path ++ [:operands], depth, :evaluate, 0, []),
         {:ok, result, state} <- operation(operator, values, state, path, depth),
         {:ok, state} <- Limits.enter(state, result, path, depth, operator) do
      {:ok, result, state}
    end
  end

  defp binary_boolean(operator, value, _right, _state, left_path, _path, _depth)
       when not is_boolean(value),
       do: type_error(:invalid_boolean_operand, operator, [value], left_path)

  defp binary_boolean(:and, false, _right, state, _left_path, _path, _depth),
    do: {:ok, false, state}

  defp binary_boolean(:or, true, _right, state, _left_path, _path, _depth),
    do: {:ok, true, state}

  defp binary_boolean(:and, true, right, state, _left_path, path, depth),
    do: visit(right, state, path ++ [:operands, 1], depth + 1, :evaluate)

  defp binary_boolean(:or, false, right, state, _left_path, path, depth),
    do: visit(right, state, path ++ [:operands, 1], depth + 1, :evaluate)

  defp host(value, %{resolve: callback} = state, path, depth, :evaluate) do
    case Limits.callback(callback, value, path) do
      {:ok, result} -> visit(result, state, path, depth, :data)
      {:error, error} -> Limits.callback_error(error, path)
      _ -> Limits.fail(:invalid_callback_return, path)
    end
  end

  defp host(_value, _state, path, _depth, :evaluate),
    do: Limits.fail(:unsupported_value, path, nil, %{type: :struct})

  defp host(value, %{validate_leaf: callback} = state, path, _depth, mode)
       when mode in [:validate, :normalize] do
    case Limits.callback(callback, value, path) do
      :ok -> {:ok, value, state}
      {:error, error} -> Limits.callback_error(error, path)
      _ -> Limits.fail(:invalid_callback_return, path)
    end
  end

  defp host(_value, _state, path, _depth, mode) when mode in [:validate, :normalize],
    do: Limits.fail(:unsupported_value, path, nil, %{type: :struct})

  defp operation(operator, [left, right], state, path, depth) when operator in [:==, :!=] do
    with {:ok, equal?, state} <- equal(left, right, state, path, depth) do
      {:ok, equality_result(operator, equal?), state}
    end
  end

  defp operation(operator, [left, right], state, path, depth)
       when operator in [:<, :<=, :>, :>=, :min, :max] do
    with {:ok, _left, state} <- visit(left, state, path, depth, :data),
         {:ok, _right, state} <- visit(right, state, path, depth, :data) do
      {:ok, compare(operator, left, right), state}
    end
  end

  defp operation(:in, [left, right], state, path, depth) do
    if proper_list?(right) do
      member(left, right, state, path, depth)
    else
      type_error(:invalid_membership_right_operand, :in, [right], path)
    end
  end

  defp operation(:not, [value], state, _path, _depth) when is_boolean(value),
    do: {:ok, not value, state}

  defp operation(:not, values, _state, path, _depth),
    do: type_error(:invalid_boolean_operand, :not, values, path)

  defp operation(:<>, [left, right], state, path, _depth)
       when is_binary(left) and is_binary(right) do
    if state.bytes + byte_size(left) + byte_size(right) > state.max_binary_bytes do
      Limits.fail(:max_binary_bytes, path, :<>)
    else
      {:ok, left <> right, state}
    end
  end

  defp operation(:<>, values, _state, path, _depth),
    do: type_error(:invalid_binary_operands, :<>, values, path)

  defp operation(operator, [left, right] = values, _state, path, _depth)
       when operator in [:+, :-, :*] and
              (not is_number(left) or not is_number(right)),
       do: type_error(:invalid_numeric_operands, operator, values, path)

  defp operation(operator, [_, _] = values, state, path, _depth)
       when operator in [:+, :-, :*],
       do: arithmetic(operator, values, state, path)

  defp operation(:/, [left, right] = values, _state, path, _depth)
       when not is_number(left) or not is_number(right),
       do: type_error(:invalid_numeric_operands, :/, values, path)

  defp operation(:/, [_left, divisor], _state, path, _depth) when divisor == 0,
    do: Limits.fail(:division_by_zero, path, :/)

  defp operation(:/, [_, _] = values, state, path, _depth),
    do: arithmetic(:/, values, state, path)

  defp operation(operator, [left, right] = values, _state, path, _depth)
       when operator in [:div, :rem] and
              (not is_integer(left) or not is_integer(right)),
       do: type_error(:invalid_numeric_operands, operator, values, path)

  defp operation(operator, [_left, 0], _state, path, _depth) when operator in [:div, :rem],
    do: Limits.fail(:division_by_zero, path, operator)

  defp operation(operator, [_, _] = values, state, path, _depth)
       when operator in [:div, :rem],
       do: arithmetic(operator, values, state, path)

  defp operation(operator, [value] = values, _state, path, _depth)
       when operator in [:-, :abs] and not is_number(value),
       do: type_error(:invalid_numeric_operands, operator, values, path)

  defp operation(operator, [_] = values, state, path, _depth)
       when operator in [:-, :abs],
       do: arithmetic(operator, values, state, path)

  defp compare(:<, left, right), do: left < right
  defp compare(:<=, left, right), do: left <= right
  defp compare(:>, left, right), do: left > right
  defp compare(:>=, left, right), do: left >= right
  defp compare(:min, left, right), do: min(left, right)
  defp compare(:max, left, right), do: max(left, right)

  defp arithmetic(operator, values, state, path) do
    {:ok, arithmetic_value(operator, values), state}
  rescue
    ArithmeticError -> Limits.fail(:arithmetic_error, path, operator)
  end

  defp arithmetic_value(:+, [left, right]), do: left + right
  defp arithmetic_value(:-, [left, right]), do: left - right
  defp arithmetic_value(:*, [left, right]), do: left * right
  defp arithmetic_value(:/, [left, right]), do: left / right
  defp arithmetic_value(:-, [value]), do: -value
  defp arithmetic_value(:div, [left, right]), do: div(left, right)
  defp arithmetic_value(:rem, [left, right]), do: rem(left, right)
  defp arithmetic_value(:abs, [value]), do: abs(value)

  defp equality_result(:==, equal?), do: equal?
  defp equality_result(:!=, equal?), do: not equal?

  defp equal(left, right, state, path, depth) do
    with {:ok, _left, state} <- visit(left, state, path, depth, :data),
         {:ok, _right, state} <- visit(right, state, path, depth, :data) do
      {:ok, left == right, state}
    end
  end

  defp member(left, values, state, path, depth),
    do: member(left, values, state, path, depth, nil)

  defp member(_left, [], state, _path, _depth, _cost), do: {:ok, false, state}

  defp member(left, [head | tail], state, path, depth, cost) do
    with {:ok, state, cost} <- membership_left(left, state, path, depth, cost),
         {:ok, _right, state} <- visit(head, state, path, depth, :data) do
      membership_result(left, head, tail, state, path, depth, cost)
    end
  end

  defp membership_result(left, head, _tail, state, _path, _depth, _cost)
       when left === head,
       do: {:ok, true, state}

  defp membership_result(left, _head, tail, state, path, depth, cost),
    do: member(left, tail, state, path, depth, cost)

  # The left value and its depth do not change during this membership scan.
  # Keep charging its full cost. Walk again near a limit to keep the first error.
  defp membership_left(_left, state, _path, _depth, {nodes, bytes} = cost)
       when state.nodes + nodes <= state.max_nodes and
              state.bytes + bytes <= state.max_binary_bytes do
    {:ok, %{state | nodes: state.nodes + nodes, bytes: state.bytes + bytes}, cost}
  end

  defp membership_left(left, state, path, depth, _cost) do
    with {:ok, _left, checked} <- visit(left, state, path, depth, :data) do
      {:ok, checked, {checked.nodes - state.nodes, checked.bytes - state.bytes}}
    end
  end

  defp proper_list?(value), do: is_list(value) and not List.improper?(value)

  defp type_error(reason, operator, values, path),
    do: Limits.fail(reason, path, operator, %{types: Enum.map(values, &Limits.type/1)})
end
