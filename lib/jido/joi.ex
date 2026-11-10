defmodule Jido.Joi do
  @moduledoc """
  The Jido data-schema facade.

  Joi exposes the part of the Zoi 0.19 schema API that Jido uses. Joi schemas
  are ordinary Zoi schemas. The facade adds Jido policies for input parsing,
  checked state initialization, exact stored-value validation, struct field
  projection, and JSON Schema projection.

  Joi defines a data lifecycle over Zoi schemas. Use `parse/3` for external
  input, where a schema can convert the input. Use `initialize/2` to create
  stored state, where checked defaults can add missing values but parsing
  cannot change supplied values. Use `validate/2` to check an existing stored
  value without adding defaults or changing the value.

  Jido map and keyword schemas use an open validation boundary by default.
  Open validation parses and validates the fields declared by the schema. It
  preserves other fields without parsing or validating them. Set
  `unrecognized_keys: :error` for a closed boundary that rejects fields that
  the schema does not declare. Stored Agent state recursively uses a closed
  boundary so that its schema describes the complete stored value. Jido does
  not use the Zoi `:strip` policy because stripping changes the data shape.
  """

  @type schema :: Zoi.schema()
  @type input :: Zoi.input()
  @type result :: Zoi.result()
  @type options :: Zoi.options()
  @type error :: Zoi.Error.t()

  # This is the curated Zoi 0.19 function surface that Jido supports.
  @zoi_delegates [
    any: 0,
    any: 1,
    array: 0,
    array: 1,
    array: 2,
    atom: 0,
    atom: 1,
    boolean: 0,
    boolean: 1,
    codec: 3,
    default: 2,
    default: 3,
    discriminated_union: 2,
    discriminated_union: 3,
    enum: 1,
    enum: 2,
    extend: 2,
    extend: 3,
    float: 0,
    float: 1,
    function: 0,
    function: 1,
    integer: 0,
    integer: 1,
    intersection: 1,
    intersection: 2,
    lazy: 1,
    lazy: 2,
    list: 0,
    list: 1,
    list: 2,
    literal: 1,
    literal: 2,
    map_set: 0,
    map_set: 1,
    map_set: 2,
    max: 2,
    max: 3,
    min: 2,
    min: 3,
    module: 0,
    module: 1,
    nullable: 1,
    nullable: 2,
    number: 0,
    number: 1,
    optional: 1,
    pid: 0,
    pid: 1,
    prettify_errors: 1,
    refine: 2,
    required: 1,
    string: 0,
    string: 1,
    string_boolean: 0,
    string_boolean: 1,
    transform: 2,
    tuple: 1,
    tuple: 2,
    type_spec: 1,
    type_spec: 2,
    union: 1,
    union: 2
  ]
  for {name, arity} <- @zoi_delegates do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Zoi
  end

  @doc "Creates an open field-based map schema."
  @spec object(map(), options()) :: schema()
  def object(fields, opts \\ []), do: Zoi.object(fields, open_options(opts))

  @doc "Creates an open keyword schema."
  @spec keyword(keyword() | schema(), options()) :: schema()
  def keyword(fields, opts \\ []), do: Zoi.keyword(fields, open_options(opts))

  @doc "Creates a closed struct schema."
  @spec struct(module(), map() | options() | nil, options()) :: schema()
  def struct(module, fields_or_opts \\ nil, opts \\ [])

  def struct(module, nil, opts),
    do: Zoi.struct(module, nil, closed_options(opts))

  def struct(module, opts, []) when is_list(opts) and opts != [],
    do: Zoi.struct(module, closed_options(opts), [])

  def struct(module, fields, opts),
    do: Zoi.struct(module, fields, closed_options(opts))

  @doc "Creates an open map schema."
  def map(), do: Zoi.map(open_options([]))
  def map(opts) when is_list(opts), do: Zoi.map(open_options(opts))
  def map(fields), do: Zoi.map(fields, open_options([]))
  def map(fields, opts) when is_list(opts), do: Zoi.map(fields, open_options(opts))
  def map(key_type, value_type), do: Zoi.map(key_type, value_type, open_options([]))
  def map(key_type, value_type, opts), do: Zoi.map(key_type, value_type, open_options(opts))

  @doc "Parse external input with a Joi schema."
  @spec parse(schema(), input(), options()) :: result()
  def parse(schema, input, opts \\ []), do: Zoi.parse(schema, input, opts)

  @doc "Parse external input and raise `Jido.Joi.ParseError` on failure."
  @spec parse!(schema(), input(), options()) :: term()
  def parse!(schema, input, opts \\ []) do
    case parse(schema, input, opts) do
      {:ok, value} -> value
      {:error, errors} -> raise Jido.Joi.ParseError, errors: errors
    end
  end

  @doc "Checks that a schema is safe for stored values."
  @spec validate_stored_schema(schema()) :: :ok | {:error, String.t()}
  def validate_stored_schema(schema) do
    with :ok <- Jido.Joi.Schema.validate_stored(schema),
         do: validate_static(schema)
  end

  @doc "Initialize stored state with checked defaults."
  @spec initialize(schema(), input()) :: result()
  def initialize(schema, input) do
    case validate_stored_schema(schema) do
      :ok -> Jido.Joi.Runtime.initialize(schema, input)
      {:error, reason} -> stored_schema_error(reason)
    end
  end

  @doc "Validate an existing stored value without changing it."
  @spec validate(schema(), input()) :: :ok | {:error, [error()]}
  def validate(schema, value) do
    case validate_stored_schema(schema) do
      :ok -> Jido.Joi.Runtime.validate(schema, value)
      {:error, reason} -> stored_schema_error(reason)
    end
  end

  @doc "Returns the required struct fields for a Joi struct schema."
  @spec enforce_keys(schema()) :: [atom()]
  def enforce_keys(schema), do: Zoi.Struct.enforce_keys(schema)

  @doc "Returns the public struct fields for a Joi struct schema."
  @spec struct_fields(schema()) :: [atom() | {atom(), term()}]
  def struct_fields(schema), do: Zoi.Struct.struct_fields(schema)

  @doc "Checks that authoring data contains no runtime-only values or dynamic schema effects."
  @spec validate_static(term()) :: :ok | {:error, String.t()}
  def validate_static(term), do: validate_static_value(term, [])

  @doc "Returns the stable code from one Joi parse issue."
  @spec error_code(error()) :: atom()
  def error_code(%{code: code}), do: code

  @doc "Returns the data path from one Joi parse issue."
  @spec error_path(error()) :: [term()]
  def error_path(%{path: path}), do: path

  @doc "Returns the message from one Joi parse issue."
  @spec error_message(error()) :: String.t()
  def error_message(%{message: message}), do: message

  @doc "Reports whether parsing would change an existing stored value."
  @spec changed_value?(error()) :: boolean()
  def changed_value?(%{code: :joi_changed_value}), do: true
  def changed_value?(_error), do: false

  @doc false
  def invalid_type_issue(type), do: Zoi.Error.invalid_type(type)

  @doc false
  def unrecognized_key_issue(key), do: Zoi.Error.unrecognized_key(key)

  @doc """
  Project a Joi schema to the common Jido JSON Schema form.

  `required` leaves out fields with a default, because parsing fills them in.
  """
  @spec to_json_schema(schema()) :: map()
  def to_json_schema(schema), do: schema |> Zoi.to_json_schema() |> drop_defaulted_required()

  defp drop_defaulted_required(json) when is_map(json) do
    json
    |> Map.new(fn
      {key, schemas} when key in [:properties, :patternProperties, :"$defs"] and is_map(schemas) ->
        {key, Map.new(schemas, fn {name, child} -> {name, drop_defaulted_required(child)} end)}

      {key, schemas} when key in [:anyOf, :oneOf, :allOf, :prefixItems] and is_list(schemas) ->
        {key, Enum.map(schemas, &drop_defaulted_required/1)}

      {key, child} when key in [:items, :additionalProperties] and is_map(child) ->
        {key, drop_defaulted_required(child)}

      other ->
        other
    end)
    |> reject_defaulted_required()
  end

  defp drop_defaulted_required(json), do: json

  defp reject_defaulted_required(%{required: required, properties: properties} = json)
       when is_list(required) and is_map(properties) do
    %{json | required: Enum.reject(required, &match?(%{default: _}, properties[&1]))}
  end

  defp reject_defaulted_required(json), do: json

  defp validate_static_value(term, path) when is_function(term),
    do: static_error("anonymous functions are not supported", path)

  defp validate_static_value(term, path)
       when is_pid(term) or is_port(term) or is_reference(term),
       do: static_error("runtime process values are not supported", path)

  defp validate_static_value(term, path) when is_map(term) do
    case Jido.Joi.Schema.kind(term) do
      :lazy ->
        static_error("lazy schemas are not supported", path)

      :meta ->
        with :ok <- validate_static_effects(Jido.Joi.Schema.effects(term), path ++ [:effects]) do
          term
          |> Map.from_struct()
          |> Map.delete(:effects)
          |> validate_static_value(path)
        end

      _other ->
        term
        |> Map.to_list()
        |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key) end)
        |> validate_static_pairs(path)
    end
  end

  defp validate_static_value(term, path) when is_list(term),
    do: validate_static_list(term, path, 0)

  defp validate_static_value(term, path) when is_tuple(term),
    do: validate_static_list(Tuple.to_list(term), path, 0)

  defp validate_static_value(_term, _path), do: :ok

  defp validate_static_pairs([], _path), do: :ok

  defp validate_static_pairs([{key, value} | rest], path) do
    with :ok <- validate_static_value(key, path ++ [:key]),
         :ok <- validate_static_value(value, path ++ [key]),
         do: validate_static_pairs(rest, path)
  end

  defp validate_static_list([], _path, _index), do: :ok

  defp validate_static_list([value | rest], path, index) when is_list(rest) do
    with :ok <- validate_static_value(value, path ++ [index]),
         do: validate_static_list(rest, path, index + 1)
  end

  defp validate_static_list([value | _tail], path, index) do
    with :ok <- validate_static_value(value, path ++ [index]),
         do: static_error("improper list tails are not supported", path ++ [index + 1])
  end

  defp validate_static_effects(effects, path) when is_list(effects) do
    effects
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {effect, index}, :ok ->
      case validate_static_effect(effect, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_static_effects(_effects, path),
    do: static_error("schema effects must be a list", path)

  defp validate_static_effect({kind, {module, function, args}}, path)
       when kind in [:refine, :transform] and is_atom(module) and is_atom(function) and
              is_list(args),
       do: validate_static_value(args, path ++ [1, 2])

  defp validate_static_effect({kind, effect}, path)
       when kind in [:refine, :transform] and is_function(effect),
       do: static_error("anonymous functions are not supported", path ++ [1])

  defp validate_static_effect(_effect, path),
    do: static_error("custom schema effects must use {Module, :function, args} MFA values", path)

  defp static_error(reason, []), do: {:error, reason}
  defp static_error(reason, path), do: {:error, "#{reason} at #{inspect(path)}"}

  defp open_options(opts), do: Keyword.put_new(opts, :unrecognized_keys, :preserve)
  defp closed_options(opts), do: Keyword.put_new(opts, :unrecognized_keys, :error)

  defp stored_schema_error(reason) do
    {:error,
     [
       Zoi.Error.new(
         code: :joi_invalid_stored_schema,
         message: reason
       )
     ]}
  end
end

defmodule Jido.Joi.ParseError do
  @moduledoc "Raised when `Jido.Joi.parse!/3` cannot parse input."
  defexception [:errors]

  @impl true
  def message(%__MODULE__{errors: errors}) when is_list(errors) do
    """
    Parsing error:

    #{Jido.Joi.prettify_errors(errors)}
    """
  end
end
