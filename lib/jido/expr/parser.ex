defmodule Jido.Expr.Parser do
  @moduledoc false

  alias Jido.Expr
  alias Jido.Expr.Limits

  @binary [
    :==,
    :!=,
    :<,
    :<=,
    :>,
    :>=,
    :in,
    :and,
    :or,
    :+,
    :-,
    :*,
    :/,
    :<>,
    :div,
    :rem,
    :min,
    :max
  ]
  @unary [:-, :not, :abs]
  @reserved Enum.uniq(@binary ++ @unary ++ [:expr])

  @doc false
  @spec syntax() :: [{atom(), pos_integer()}]
  def syntax do
    Enum.map(@binary, &{&1, 2}) ++ Enum.map(@unary, &{&1, 1})
  end

  @doc false
  @spec parse(Macro.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def parse(ast, options), do: run(ast, options, false)

  @doc false
  @spec expand!(Macro.t()) :: Macro.t()
  def expand!(ast) do
    case run(ast, [], true) do
      {:ok, expression} -> Macro.escape(expression, unquote: true)
      {:error, error} -> raise error
    end
  end

  defp run(ast, options, pins?) do
    with {:ok, state} <- Limits.new(options, [:leaf_parser]),
         {:ok, result, _state} <- walk(ast, Map.put(state, :pins?, pins?), [], 0) do
      if is_struct(result, Expr), do: {:ok, result}, else: Limits.fail(:expected_expression, [])
    end
  end

  defp walk(ast, state, path, depth) do
    with {:ok, state} <- Limits.enter(state, ast, path, depth) do
      node(ast, state, path, depth)
    end
  end

  defp node(%Expr{operator: operator, operands: operands}, state, path, depth),
    do: operation(operator, operands, state, path, depth)

  defp node(%_{} = value, state, path, _depth), do: leaf(value, state, path)
  defp node({:expr, _, [ast]}, state, path, depth), do: walk(ast, state, path, depth)

  defp node({name, _, [left, right]}, state, path, depth) when name in @binary,
    do: operation(name, [left, right], state, path, depth)

  defp node({name, _, [operand]}, state, path, depth) when name in @unary,
    do: operation(name, [operand], state, path, depth)

  defp node({name, _, _args}, _state, path, _depth) when name in @reserved,
    do: Limits.fail(:invalid_arity, path)

  defp node(
         {:^, _, [{name, metadata, context} = variable]},
         %{pins?: true} = state,
         _path,
         _depth
       )
       when is_atom(name) and is_list(metadata) and is_atom(context),
       do: {:ok, {:unquote, [], [variable]}, state}

  defp node({:^, _, _}, _state, path, _depth), do: Limits.fail(:unsupported_syntax, path)

  defp node({:%{}, _, pairs}, state, path, depth) when is_list(pairs),
    do: map(pairs, state, path, depth, %{})

  defp node(value, state, path, depth) when is_map(value),
    do: map_iterator(:maps.iterator(value), state, path, depth, %{})

  defp node(values, state, path, depth) when is_list(values),
    do: list(values, state, path, depth, 0, [])

  defp node(value, state, _path, _depth)
       when is_atom(value) or is_number(value) or is_binary(value),
       do: {:ok, value, state}

  defp node(ast, state, path, _depth), do: leaf(ast, state, path)

  defp operation(operator, operands, state, path, depth) do
    with {:ok, parsed, state} <- list(operands, state, path ++ [:operands], depth, 0, []),
         {:ok, expression} <- Expr.new(operator, parsed) do
      {:ok, expression, state}
    else
      {:error, %Jido.Expr.Error{path: []} = error} -> {:error, %{error | path: path}}
      error -> error
    end
  end

  defp list([], state, _path, _depth, _index, values), do: {:ok, Enum.reverse(values), state}

  defp list([head | tail], state, path, depth, index, values) do
    with {:ok, value, state} <- walk(head, state, path ++ [index], depth + 1) do
      list(tail, state, path, depth, index + 1, [value | values])
    end
  end

  defp list(_tail, _state, path, _depth, index, _values),
    do: Limits.fail(:improper_list, path ++ [index])

  defp map([], state, _path, _depth, values), do: {:ok, values, state}

  defp map([{key, value} | tail], state, path, depth, values) do
    with {:ok, values, state} <- map_pair(key, value, state, path, depth, values) do
      map(tail, state, path, depth, values)
    end
  end

  defp map(_pairs, _state, path, _depth, _values), do: Limits.fail(:invalid_map_key, path)

  defp map_iterator(iterator, state, path, depth, values) do
    case :maps.next(iterator) do
      :none ->
        {:ok, values, state}

      {key, value, iterator} ->
        with {:ok, values, state} <- map_pair(key, value, state, path, depth, values) do
          map_iterator(iterator, state, path, depth, values)
        end
    end
  end

  defp map_pair(key, value, state, path, depth, values)
       when is_atom(key) or is_binary(key) or is_integer(key) do
    if Map.has_key?(values, key) do
      Limits.fail(:duplicate_key, path ++ [key])
    else
      with {:ok, state} <- Limits.enter(state, key, path ++ [key], depth + 1),
           {:ok, value, state} <- walk(value, state, path ++ [key], depth + 1) do
        {:ok, Map.put(values, key, value), state}
      end
    end
  end

  defp map_pair(_key, _value, _state, path, _depth, _values),
    do: Limits.fail(:invalid_map_key, path)

  defp leaf(ast, state, path) do
    case Map.get(state, :leaf_parser) do
      nil ->
        Limits.fail(:unsupported_syntax, path)

      callback ->
        case Limits.callback(callback, ast, []) do
          {:ok, value} -> {:ok, value, state}
          :error -> Limits.fail(:unsupported_syntax, path)
          {:error, error} -> Limits.callback_error(error, path)
          _ -> Limits.fail(:invalid_callback_return, path)
        end
    end
  end
end
