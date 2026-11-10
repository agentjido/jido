defmodule Jido.Expr.Limits do
  @moduledoc false

  alias Jido.Expr.Error

  @defaults [
    max_depth: 64,
    max_nodes: 10_000,
    max_binary_bytes: 1_048_576,
    max_integer_bits: 4096
  ]

  @doc false
  @spec new(keyword(), [atom()]) :: {:ok, map()} | {:error, Error.t()}
  def new(options, callbacks) do
    if valid_options?(options, callbacks) do
      limits = Map.new(Keyword.merge(@defaults, options))

      {:ok,
       Map.merge(limits, %{
         nodes: 0,
         bytes: 0,
         integer_bound: Bitwise.bsl(1, limits.max_integer_bits)
       })}
    else
      {:error, %Error{reason: :invalid_options}}
    end
  end

  @doc false
  @spec enter(map(), term(), list(), non_neg_integer(), atom() | nil) ::
          {:ok, map()} | {:error, Error.t()}
  def enter(state, value, path, depth, operator \\ nil) do
    bytes = if is_binary(value), do: byte_size(value), else: 0
    state = %{state | nodes: state.nodes + 1, bytes: state.bytes + bytes}

    cond do
      depth > state.max_depth ->
        fail(:max_depth, path, operator)

      state.nodes > state.max_nodes ->
        fail(:max_nodes, path, operator)

      state.bytes > state.max_binary_bytes ->
        fail(:max_binary_bytes, path, operator)

      is_integer(value) and (value >= state.integer_bound or value <= -state.integer_bound) ->
        fail(:max_integer_bits, path, operator)

      true ->
        {:ok, state}
    end
  end

  @doc false
  @spec fail(atom(), list(), atom() | nil, map()) :: {:error, Error.t()}
  def fail(reason, path, operator \\ nil, details \\ %{}),
    do: {:error, %Error{reason: reason, path: path, operator: operator, details: details}}

  @doc false
  @spec type(term()) :: atom()
  def type(value) when is_nil(value), do: nil
  def type(value) when is_boolean(value), do: :boolean
  def type(value) when is_integer(value), do: :integer
  def type(value) when is_float(value), do: :float
  def type(value) when is_binary(value), do: :binary
  def type(value) when is_atom(value), do: :atom
  def type(value) when is_list(value), do: :list
  def type(value) when is_tuple(value), do: :tuple
  def type(value) when is_map(value), do: :map
  def type(_value), do: :other

  @doc false
  @spec callback(function(), term(), list()) :: term()
  def callback(callback, value, path) do
    if is_function(callback, 2), do: callback.(value, path), else: callback.(value)
  rescue
    _ -> fail(:callback_failure, [])
  catch
    _, _ -> fail(:callback_failure, [])
  end

  @doc false
  @spec callback_error(term(), list()) :: {:error, term()}
  def callback_error(%Error{} = error, path), do: {:error, %{error | path: path ++ error.path}}
  def callback_error(error, _path), do: {:error, error}

  defp valid_options?(options, callbacks) do
    Keyword.keyword?(options) and
      Enum.all?(options, fn {key, value} ->
        cond do
          Keyword.has_key?(@defaults, key) ->
            is_integer(value) and value > 0 and value <= 1_048_576_000 and
              (key != :max_integer_bits or value <= 1_048_576)

          key in callbacks ->
            is_function(value, 1) or (key != :leaf_parser and is_function(value, 2))

          true ->
            false
        end
      end)
  end
end
