defmodule Jido.Flow.Value do
  @moduledoc """
  Defines the canonical Flow value union.

  A Flow value is portable literal data, a nested list or map of values, a
  `Jido.Flow.Ref`, or a `Jido.Expr` operation.

  The complete value tree can contain up to 256 levels and 100,000 nodes.
  Each expression also uses the smaller standard limits from `Jido.Expr`.
  """

  alias Jido.Authoring.Config
  alias Jido.Expr
  alias Jido.Flow.Error
  alias Jido.Flow.Ref

  @tree_options [
    max_depth: 256,
    max_nodes: 100_000,
    max_binary_bytes: 1_048_576_000,
    max_integer_bits: 1_048_576
  ]

  @typedoc "A portable scalar value."
  @type scalar :: nil | boolean() | number() | String.t() | atom()

  @typedoc "A portable map key."
  @type key :: String.t() | non_neg_integer() | atom()

  @typedoc "A portable data value without Flow references or expressions."
  @type data :: scalar() | [data()] | %{optional(key()) => data()}

  @typedoc "A portable data object."
  @type object :: %{optional(key()) => data()}

  @typedoc "Canonical portable Flow value."
  @type t ::
          scalar()
          | [t()]
          | %{optional(key()) => t()}
          | Ref.t()
          | Expr.t()

  @doc false
  @spec normalize(term()) :: {:ok, term()} | {:error, Exception.t()}
  def normalize(expression) do
    with {:ok, expression} <-
           Expr.normalize(
             expression,
             Keyword.merge(@tree_options,
               normalize_leaf: &normalize_leaf/2,
               validate_leaf: &validate_normalized_leaf/2
             )
           ),
         :ok <- validate_expression_limits(expression) do
      {:ok, expression}
    end
    |> operation_result([])
  end

  @doc false
  @spec validate(term(), Ref.scope()) :: :ok | {:error, Exception.t()}
  def validate(expression, scope \\ :flow) do
    validate_tree(expression, scope, true)
  end

  @doc "Validates portable Flow data without references or expressions."
  @spec validate_data(term()) :: :ok | {:error, Error.InvalidDefinitionError.t()}
  def validate_data(value) do
    value
    |> Expr.reduce(nil, &validate_data_node/3, @tree_options)
    |> validation_result()
  end

  @doc "Validates a portable Flow metadata object."
  @spec validate_object(term()) :: :ok | {:error, Error.InvalidDefinitionError.t()}
  def validate_object(value) when is_map(value) and not is_struct(value),
    do: validate_data(value)

  def validate_object(_value) do
    {:error, Error.validation_error("flow metadata must be a portable map")}
  end

  @doc false
  @spec validate_key(term()) :: :ok | {:error, Error.InvalidDefinitionError.t()}
  def validate_key(key), do: validate_key(key, [])

  @doc false
  @spec prepare(term(), Ref.scope()) :: {:ok, term()} | {:error, Exception.t()}
  def prepare(expression, scope \\ :flow) do
    with {:ok, expression} <- normalize(expression),
         :ok <- validate_tree(expression, scope, false) do
      {:ok, expression}
    end
  end

  @doc false
  @spec condition(term(), Ref.scope()) ::
          {:ok, boolean() | Ref.t() | Expr.t()} | {:error, Exception.t()}
  def condition(value, scope)
      when is_struct(value, Expr) or is_struct(value, Ref) or is_boolean(value),
      do: prepare(value, scope)

  def condition(_value, _scope),
    do:
      {:error,
       Error.validation_error("condition must be a Boolean, Flow reference, or Jido.Expr", %{
         path: []
       })}

  @doc false
  @spec to_map(term()) :: term()
  # Keep the struct tags distinct from literal maps with the same fields.
  def to_map(%Ref{} = ref), do: ref

  def to_map(%Expr{} = expr), do: %{expr | operands: Enum.map(expr.operands, &to_map/1)}

  def to_map(%{} = map) do
    Map.new(map, fn {key, value} -> {key, to_map(value)} end)
  end

  def to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  def to_map(value), do: value

  @doc false
  @spec result_refs(term()) :: [String.t()]
  def result_refs(value) do
    reducer = fn
      %Ref{source: :result, component: component}, _path, refs ->
        {:cont, [component | refs]}

      _value, _path, refs ->
        {:cont, refs}
    end

    case Expr.reduce(value, [], reducer, @tree_options) do
      {:ok, refs} -> Enum.reverse(refs)
      {:error, _error} -> []
    end
  end

  defp validate_tree(expression, scope, validate_expressions?) do
    state = %{expression_root: nil, scope: scope, validate_expressions?: validate_expressions?}

    expression
    |> Expr.reduce(state, &validate_node/3, @tree_options)
    |> validation_result()
  end

  defp validate_node(%Expr{} = expression, path, state) do
    if state.validate_expressions? and not inside_expression?(path, state.expression_root) do
      case validate_expression(expression, path) do
        :ok -> {:cont, %{state | expression_root: path}}
        {:error, error} -> {:error, error}
      end
    else
      {:cont, state}
    end
  end

  defp validate_node(%Ref{} = ref, path, state) do
    case validate_ref(ref, path, state.scope) do
      :ok -> {:cont, state}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_node(%{} = map, path, state) when not is_struct(map) do
    case validate_map_keys(map, path) do
      :ok -> {:cont, state}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_node(list, path, state) when is_list(list) do
    if List.improper?(list) do
      {:error, improper_list_exception(path)}
    else
      {:cont, state}
    end
  end

  defp validate_node(%{__struct__: module}, path, _scope) do
    {:error,
     Error.validation_error("flow expression contains an unsupported value", %{
       path: path,
       expression: module
     })}
  end

  defp validate_node(value, path, state) do
    case validate_scalar(value, path) do
      :ok -> {:cont, state}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_expression_limits(expression) do
    expression
    |> Expr.reduce(nil, &validate_expression_root/3, @tree_options)
    |> validation_result()
  end

  defp validate_expression_root(%Expr{} = expression, path, expression_root) do
    if inside_expression?(path, expression_root) do
      {:cont, expression_root}
    else
      case validate_expression(expression, path) do
        :ok -> {:cont, path}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp validate_expression_root(_value, _path, expression_root),
    do: {:cont, expression_root}

  defp validate_expression(expression, path) do
    expression
    |> Expr.validate(validate_leaf: fn _value -> :ok end)
    |> operation_result(path)
  end

  defp inside_expression?(_path, nil), do: false

  defp inside_expression?(path, root_path) do
    path != root_path and List.starts_with?(path, root_path)
  end

  defp validate_ref(%Ref{} = ref, path, scope) do
    case Ref.validate(ref, scope) do
      :ok ->
        :ok

      {:error, %{details: %{reason: :path, segment: segment}}} ->
        {:error,
         Error.validation_error("flow expression contains an invalid reference path", %{
           path: path,
           segment: segment
         })}

      {:error, %{details: %{reason: :scope, source: type, scope: invalid_scope}}} ->
        {:error,
         Error.validation_error(
           "flow expression contains a scoped ref outside its valid scope",
           %{path: path, ref_type: type, scope: invalid_scope}
         )}

      {:error, _error} ->
        invalid_ref_error(ref.source, path)
    end
  end

  defp validate_normalized_leaf(%Ref{} = ref, path), do: validate_ref(ref, path, :any)

  defp validate_normalized_leaf(%{__struct__: module}, path) do
    {:error,
     Error.validation_error("flow expression contains an unsupported value", %{
       path: path,
       expression: module
     })}
  end

  defp validate_data_node(%{} = map, path, accumulator) when not is_struct(map) do
    case validate_map_keys(map, path) do
      :ok -> {:cont, accumulator}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_data_node(list, path, accumulator) when is_list(list) do
    if List.improper?(list) do
      {:error, data_error("flow data must contain proper lists", path)}
    else
      {:cont, accumulator}
    end
  end

  defp validate_data_node(value, path, accumulator) do
    case validate_scalar(value, path) do
      :ok -> {:cont, accumulator}
      {:error, error} -> {:error, error}
    end
  end

  defp validate_map_keys(map, path) do
    Enum.reduce_while(map, :ok, fn {key, _value}, :ok ->
      case validate_key(key, path) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_key(key, path) when is_binary(key), do: validate_scalar(key, path)

  defp validate_key(key, _path)
       when (is_integer(key) and key >= 0) or (is_atom(key) and not is_nil(key)),
       do: :ok

  defp validate_key(key, path) do
    {:error,
     Error.validation_error("flow data contains an unsupported map key", %{
       path: path,
       key: key
     })}
  end

  defp validate_scalar(value, _path)
       when is_nil(value) or is_boolean(value) or is_integer(value) or is_float(value) or
              is_atom(value),
       do: :ok

  defp validate_scalar(value, path) when is_binary(value) do
    if String.valid?(value),
      do: :ok,
      else: {:error, data_error("flow data strings must be valid UTF-8", path)}
  end

  defp validate_scalar(value, path) do
    {:error,
     Error.validation_error("flow data contains an unsupported value", %{
       path: path,
       value_type: value_type(value)
     })}
  end

  defp validation_result({:ok, _accumulator}), do: :ok

  defp validation_result({:error, %Expr.Error{} = error}),
    do: operation_result({:error, error}, [])

  defp validation_result({:error, _error} = error), do: error

  defp normalize_leaf(%Ref{source: :result, component: component} = ref, path)
       when (is_atom(component) and not is_nil(component)) or is_binary(component) do
    case normalize_name(component) do
      {:ok, component} -> {:ok, %{ref | component: component}}
      {:error, error} -> {:error, Error.prefix_path(error, path)}
    end
  end

  defp normalize_leaf(%Ref{} = ref, _path), do: {:ok, ref}
  defp normalize_leaf(value, _path), do: {:ok, value}

  defp normalize_name(name) when is_atom(name) and not is_nil(name) do
    name |> Atom.to_string() |> normalize_name()
  end

  defp normalize_name(name) when is_binary(name) do
    case Config.validate_name(name) do
      :ok -> {:ok, name}
      {:error, message} -> {:error, Error.validation_error(message)}
    end
  end

  defp normalize_name(_name) do
    {:error, Error.validation_error("component name must be a non-empty string or atom")}
  end

  defp invalid_ref_error(type, path) do
    {:error,
     Error.validation_error("flow expression contains an invalid reference", %{
       path: path,
       ref_type: type
     })}
  end

  defp improper_list_exception(path),
    do:
      Error.validation_error("flow expression must be a proper list", %{
        path: path,
        reason: :improper_list
      })

  defp data_error(message, path), do: Error.validation_error(message, %{path: path})

  defp value_type(value) when is_tuple(value), do: :tuple
  defp value_type(value) when is_function(value), do: :function
  defp value_type(value) when is_pid(value), do: :pid
  defp value_type(value) when is_reference(value), do: :reference
  defp value_type(%{__struct__: module}), do: {:struct, module}
  defp value_type(_value), do: :other

  defp operation_result({:error, %Expr.Error{} = error}, path) do
    {:error,
     Error.validation_error("invalid Flow expression", %{
       path: path ++ error.path,
       operator: error.operator,
       reason: error.reason
     })}
  end

  defp operation_result({:error, error}, path), do: {:error, Error.prefix_path(error, path)}
  defp operation_result(result, _path), do: result
end
