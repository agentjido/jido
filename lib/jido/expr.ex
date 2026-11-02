defmodule Jido.Expr do
  @moduledoc """
  Small, data-only expressions for limited use in Flow DSLs.

  Use `Jido.Expr` for simple conditions and calculations in Flow parameters,
  outputs, and other DSL fields. It is not a general Elixir evaluator or a
  general-purpose expression language. Expressions contain fixed operators
  and data. They never contain executable callbacks.

  Other small, data-only DSLs can use the same syntax through `parse/2`. Each
  host supplies its own reference parser, validator, and resolver. These
  callbacks can handle leaf values. They cannot add operators. This module
  does not depend on a host package or a reference namespace.

  ## Author expressions

      import Jido.Expr, only: [expr: 1]

      calculation = expr(2 * 3 + 1)
      {:ok, 7} = Jido.Expr.evaluate(calculation)

  Use `^value` in `expr/1` to insert a prebuilt value or host reference from
  an Elixir variable. This is a trusted source-code boundary, not stored
  expression syntax. Application calls, including calls inside a pin, are
  rejected. A host parser does not accept pins by default.

  The grammar is a small subset of Elixir expression syntax. It supports `==`,
  `!=`, `<`, `<=`, `>`, `>=`, `in`, `and`, `or`, `not`, `+`, binary and unary
  `-`, `*`, `/`, `div/2`, `rem/2`, `min/2`, `max/2`, `abs/1`, and `<>`.
  Conformance tests list every accepted spelling and compare each supported
  operation with the equivalent Elixir expression. These tests enforce
  consistent syntax, precedence, grouping, and success or failure behavior
  for the supported subset.

  `and` and `or` require a Boolean left operand, short-circuit, and return the
  evaluated right operand unchanged. `not` requires a Boolean. Parentheses
  preserve native grouping and precedence; binary Boolean groups are not
  flattened.

  Equality uses `==`; list membership uses strict `===` and requires a proper
  list. Ordering and `min`/`max` use Elixir term order, including mixed types.
  Arithmetic accepts numbers; `div` and `rem` require integers. Concatenation
  accepts binaries. There is no implicit conversion.

  Literal data consists of atoms (including nil and Booleans), numbers,
  binaries, proper lists, and maps with atom, integer, or binary keys. Host
  references can supply data within the host's contract and the limits below.
  Unsupported source forms, including tuples, ranges, arbitrary calls, unary
  `+`, `&&`, `||`, and strict equality syntax, are rejected.

  ## Resource limits

  `parse/2`, `normalize/2`, `reduce/4`, `validate/2`, and `evaluate/2` accept
  positive integer limits:

  * `:max_depth` defaults to 64 nested data or expression levels.
  * `:max_nodes` defaults to 10,000 visited values, including resolved data
    and comparison work during evaluation.
  * `:max_binary_bytes` defaults to 1,048,576 cumulative bytes in visited
    binaries and generated results.
  * `:max_integer_bits` defaults to 4,096 bits in each integer magnitude.

  Limits cannot exceed 1,048,576,000. `:max_integer_bits` has a lower maximum
  of 1,048,576 to keep the limit check itself bounded.

  Limits apply to each call. Skipped operands are not resolved or evaluated.
  Validation checks the complete tree. Resolve and validation callbacks belong
  to trusted host code and must themselves be bounded.
  Resolved values are checked as data and are never evaluated as expressions.
  """

  alias Jido.Expr.{Error, Parser, Runtime}

  @operations [
    {:==, 2},
    {:!=, 2},
    {:<, 2},
    {:<=, 2},
    {:>, 2},
    {:>=, 2},
    {:in, 2},
    {:and, 2},
    {:or, 2},
    {:not, 1},
    {:+, 2},
    {:-, 2},
    {:-, 1},
    {:*, 2},
    {:/, 2},
    {:div, 2},
    {:rem, 2},
    {:min, 2},
    {:max, 2},
    {:abs, 1},
    {:<>, 2}
  ]
  @operator_names @operations |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  @enforce_keys [:operator, :operands]
  defstruct [:operator, :operands]

  @typedoc "One fixed operation with data or nested expression operands."
  @type t :: %__MODULE__{operator: atom(), operands: [term()]}

  @typedoc "A path within an expression tree."
  @type path :: [atom() | integer() | String.t()]

  @typedoc "One resource limit option."
  @type limit_option ::
          {:max_depth, pos_integer()}
          | {:max_nodes, pos_integer()}
          | {:max_binary_bytes, pos_integer()}
          | {:max_integer_bits, pos_integer()}

  @typedoc "Options accepted by `parse/2`."
  @type parse_option :: limit_option() | {:leaf_parser, (Macro.t() -> term())}
  @type parse_options :: [parse_option()]

  @typedoc "Options accepted by `validate/2`."
  @type validate_option ::
          limit_option()
          | {:validate_leaf, (term() -> term()) | (term(), path() -> term())}

  @type validate_options :: [validate_option()]

  @typedoc "Options accepted by `normalize/2`."
  @type normalize_option ::
          limit_option()
          | {:normalize_leaf, (term() -> term()) | (term(), path() -> term())}
          | {:validate_leaf, (term() -> term()) | (term(), path() -> term())}

  @type normalize_options :: [normalize_option()]

  @typedoc "One result from a `reduce/4` callback."
  @type reduce_result(accumulator) ::
          {:cont, accumulator} | {:halt, accumulator} | {:error, term()}

  @typedoc "A callback accepted by `reduce/4`."
  @type reducer(accumulator) ::
          (term(), accumulator -> reduce_result(accumulator))
          | (term(), path(), accumulator -> reduce_result(accumulator))

  @typedoc "Options accepted by `evaluate/2`."
  @type evaluate_option ::
          limit_option()
          | {:resolve, (term() -> term()) | (term(), path() -> term())}

  @type evaluate_options :: [evaluate_option()]

  @doc "Returns the closed list of supported Elixir operators and arities."
  @spec operations() :: [{atom(), pos_integer()}]
  def operations, do: @operations

  @doc "Constructs an expression after checking its operator and operand arity."
  @spec new(atom(), [term()]) :: {:ok, t()} | {:error, Error.t()}
  def new(operator, operands) do
    cond do
      operator not in @operator_names ->
        {:error, %Error{reason: :unknown_operator, operator: safe_operator(operator)}}

      not valid_operands?(operator, operands) ->
        {:error, %Error{reason: :invalid_arity, operator: operator}}

      true ->
        {:ok, %__MODULE__{operator: operator, operands: operands}}
    end
  end

  @doc "Constructs an expression, or raises `Jido.Expr.Error`."
  @spec new!(atom(), [term()]) :: t()
  def new!(operator, operands), do: unwrap!(new(operator, operands))

  @doc """
  Parses quoted source with the shared, inert expression grammar.

  `:leaf_parser` can be a function that accepts an unknown AST node and
  returns `{:ok, host_value}`, `:error`, or `{:error, error}`. The fixed
  operator grammar takes precedence. Host errors pass through unchanged;
  a returned `Jido.Expr.Error` path is relative to the parsed location.
  The callback is trusted authoring code, not stored in the result. Neither
  this function nor its default grammar evaluates source.
  """
  @spec parse(Macro.t(), parse_options()) :: {:ok, t()} | {:error, term()}
  def parse(ast, options \\ []), do: Parser.parse(ast, options)

  @doc "Parses quoted source, or raises on a parse failure."
  @spec parse!(Macro.t(), parse_options()) :: t()
  def parse!(ast, options \\ []), do: unwrap!(parse(ast, options))

  @doc "Builds expression data from source; `^variable` inserts trusted host data."
  @spec expr(Macro.t()) :: Macro.t()
  defmacro expr(ast), do: Parser.expand!(ast)

  @doc """
  Normalizes an expression or a data tree without evaluating operations.

  A `:normalize_leaf` callback can replace a host struct. It must return
  `{:ok, value}` or `{:error, error}`. A `:validate_leaf` callback then checks
  every host struct that remains. Each callback can accept the current path as
  its second argument.

  The walk accepts expression nodes, host structs, maps, proper lists, and
  literal expression data. It applies the standard expression limits to the
  complete input tree.
  """
  @spec normalize(term(), normalize_options()) :: {:ok, term()} | {:error, term()}
  def normalize(value, options \\ []), do: Runtime.normalize(value, options)

  @doc """
  Reduces an expression or data tree with limits and exact paths.

  The reducer receives each value before its children. An arity-three reducer
  also receives the current path. Return `{:cont, accumulator}` to visit the
  children, `{:halt, accumulator}` to stop successfully, or `{:error, error}`
  to stop with an error.

  Expression operand paths contain `:operands` and a zero-based index. List
  paths contain an index. Map value paths contain the map key. The reducer
  receives each map, so it can inspect its keys. Map keys count toward the
  resource limits but are not separate reducer values. Host structs are
  leaves.
  """
  @spec reduce(term(), accumulator, reducer(accumulator), [limit_option()]) ::
          {:ok, accumulator} | {:error, term()}
        when accumulator: term()
  def reduce(value, accumulator, reducer, options \\ []),
    do: Runtime.reduce(value, accumulator, reducer, options)

  @doc """
  Validates a complete expression tree without running operations.

  A `:validate_leaf` callback can accept a host struct and return `:ok` or
  `{:error, error}`. Unknown structs otherwise fail validation. Callback
  errors pass through unchanged; expression errors include their tree path.
  An arity-two callback also receives the current path. A returned
  `Jido.Expr.Error` path is relative to that location.
  """
  @spec validate(t(), validate_options()) :: :ok | {:error, term()}
  def validate(value, options \\ []), do: Runtime.validate(value, options)

  @doc """
  Evaluates an expression tree with bounded fixed operations.

  A `:resolve` callback accepts a host struct and returns `{:ok, value}` or
  `{:error, error}`. Unknown structs otherwise fail. Returned data is not
  interpreted as expression code. Host errors pass through unchanged.
  An arity-two callback also receives the current path. A returned
  `Jido.Expr.Error` path is relative to that location.
  """
  @spec evaluate(t(), evaluate_options()) :: {:ok, term()} | {:error, term()}
  def evaluate(value, options \\ []), do: Runtime.evaluate(value, options)

  defp valid_operands?(operator, [_]), do: {operator, 1} in @operations
  defp valid_operands?(operator, [_, _]), do: {operator, 2} in @operations
  defp valid_operands?(_operator, _operands), do: false

  defp safe_operator(operator) when is_atom(operator), do: operator
  defp safe_operator(_), do: nil
  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: raise(error)
end
