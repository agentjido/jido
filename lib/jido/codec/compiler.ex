defmodule Jido.Codec.Compiler do
  @moduledoc false

  alias Jido.Joi
  alias Jido.Joi.Schema

  @field_options [:as, :decode, :encode, :omit]
  @codec_options [:schema]

  def using(opts, env) do
    unless Keyword.keyword?(opts) do
      compile_error!(env, "codec options must be a keyword list")
    end

    case Keyword.validate(opts, @codec_options) do
      {:ok, _opts} -> :ok
      {:error, keys} -> compile_error!(env, "unknown codec options: #{inspect(keys)}")
    end

    schema = Keyword.fetch!(opts, :schema)

    quote do
      Module.register_attribute(__MODULE__, :jido_codec_fields, accumulate: true)
      @jido_codec_schema unquote(schema)
      @before_compile Jido.Codec.Compiler

      import Jido.Codec.Compiler, only: [codec: 1, codec: 2]
    end
  end

  defmacro codec(field, opts \\ []) do
    caller = __CALLER__
    field = Macro.expand(field, caller)
    opts = expand_options!(opts, caller, @field_options)

    unless is_atom(field) or is_binary(field) do
      compile_error!(caller, "codec field must be an atom or string")
    end

    case Keyword.validate(opts, @field_options) do
      {:ok, opts} -> validate_field_options!(field, opts, caller)
      {:error, keys} -> compile_error!(caller, "unknown codec field options: #{inspect(keys)}")
    end

    quote bind_quoted: [field: field, opts: opts] do
      @jido_codec_fields {field, opts}
    end
  end

  defmacro __before_compile__(env) do
    schema = Module.get_attribute(env.module, :jido_codec_schema)
    field_declarations = Module.get_attribute(env.module, :jido_codec_fields)
    field_options = field_options!(field_declarations, env)
    validate_schema!(schema, env)
    plan = compile_plan!(schema, field_options, env)
    json_schema = schema |> Joi.to_json_schema() |> wire_json_schema(plan, env.module)
    functions = functions_ast(schema, plan, json_schema)
    encoder = encoder_ast(schema, env.module, env)

    quote do
      unquote(functions)
      unquote(encoder)
    end
  end

  defp functions_ast(schema, plan, json_schema) do
    quote do
      @doc "Decodes a JSON object with this module's Joi schema."
      @spec decode(binary()) :: {:ok, term()} | {:error, term()}
      def decode(json) when is_binary(json) do
        with {:ok, value} <- JSON.decode(json),
             do: from_map(value)
      end

      def decode(_value), do: {:error, [Joi.invalid_type_issue(:string)]}

      @doc "Decodes a JSON object or raises on invalid input."
      @spec decode!(binary()) :: term()
      def decode!(json) when is_binary(json), do: json |> JSON.decode!() |> from_map!()

      @doc "Converts a decoded JSON object with this module's Joi schema."
      @spec from_map(map()) :: {:ok, term()} | {:error, term()}
      def from_map(value) do
        Jido.Codec.Compiler.from_map(
          value,
          unquote(Macro.escape(schema)),
          unquote(Macro.escape(plan)),
          __MODULE__
        )
      end

      @doc "Converts a decoded JSON object or raises on invalid input."
      @spec from_map!(map()) :: term()
      def from_map!(value) do
        Jido.Codec.Compiler.from_map!(
          value,
          unquote(Macro.escape(schema)),
          unquote(Macro.escape(plan)),
          __MODULE__
        )
      end

      @doc "Projects a codec value to JSON-shaped data."
      @spec dump(term()) :: map()
      def dump(value) do
        Jido.Codec.Compiler.dump(value, unquote(Macro.escape(plan)), __MODULE__)
      end

      @doc "Returns the JSON Schema of this module's wire shape."
      @spec json_schema() :: map()
      def json_schema, do: unquote(Macro.escape(json_schema))

      @doc false
      def __jido_codec__, do: true
    end
  end

  defp wire_json_schema(json, {:struct, module, fields, _unknown}, owner) do
    if module != owner and compiled_codec?(module),
      do: Map.delete(module.json_schema(), :"$schema"),
      else: wire_fields(json, fields, owner)
  end

  defp wire_json_schema(json, {:object, fields, _unknown}, owner),
    do: wire_fields(json, fields, owner)

  defp wire_json_schema(%{items: items} = json, {:array, inner}, owner),
    do: %{json | items: wire_json_schema(items, inner, owner)}

  defp wire_json_schema(%{anyOf: variants} = json, {:union, branches}, owner)
       when length(variants) == length(branches) do
    variants =
      variants
      |> Enum.zip(branches)
      |> Enum.map(fn {variant, {_schema, plan}} -> wire_json_schema(variant, plan, owner) end)

    %{json | anyOf: variants}
  end

  defp wire_json_schema(json, _plan, _owner), do: json

  defp wire_fields(%{properties: properties, required: required} = json, fields, owner) do
    wire_names = Map.new(fields, fn {field, key, _plan, _opts} -> {field, wire_name(field, key)} end)

    properties =
      Map.new(fields, fn {field, _key, plan, _opts} ->
        {wire_names[field], wire_json_schema(properties[field], plan, owner)}
      end)

    omitted = for {field, _key, _plan, opts} <- fields, Keyword.get(opts, :omit, false) == nil, do: field

    %{
      json
      | properties: properties,
        required: for(field <- required, field not in omitted, do: wire_names[field])
    }
  end

  defp wire_fields(json, _fields, _owner), do: json

  defp wire_name(field, key), do: if(default_json_key(field) == key, do: field, else: key)

  defp compiled_codec?(module),
    do: match?({:module, ^module}, Code.ensure_compiled(module)) and codec_module?(module)

  defp field_options!(declarations, env) do
    options = Map.new(declarations)

    if length(declarations) != map_size(options),
      do: compile_error!(env, "each codec field can be declared only once"),
      else: options
  end

  @doc false
  def from_map(value, schema, plan, owner) do
    with {:ok, decoded} <- decode_value(value, plan, owner, []),
         do: Joi.parse(schema, decoded)
  rescue
    error -> {:error, error}
  end

  @doc false
  def from_map!(value, schema, plan, owner) do
    case decode_value(value, plan, owner, []) do
      {:ok, decoded} -> Joi.parse!(schema, decoded)
      {:error, errors} when is_list(errors) -> raise Jido.Joi.ParseError, errors: errors
      {:error, error} -> raise error
    end
  end

  @doc false
  def dump(value, plan, owner), do: encode_value(value, plan, owner)

  defp expand_options!(opts, env, allowed) do
    opts = Macro.expand(opts, env)

    unless Keyword.keyword?(opts) do
      compile_error!(env, "codec options must be a keyword list")
    end

    case Keyword.validate(opts, allowed) do
      {:ok, opts} -> Enum.map(opts, fn {key, value} -> {key, expand_value(value, env)} end)
      {:error, keys} -> compile_error!(env, "unknown codec options: #{inspect(keys)}")
    end
  end

  defp expand_value({:@, _meta, [{name, _name_meta, _context}]}, env),
    do: Module.get_attribute(env.module, name)

  defp expand_value(value, env), do: Macro.expand(value, env)

  defp validate_schema!(schema, env) do
    unless Schema.schema?(schema) do
      compile_error!(env, "schema must be a Joi schema, got: #{inspect(schema)}")
    end

    unless Schema.kind(schema) in [:struct, :map] do
      compile_error!(env, "codec schema must describe a struct or map")
    end

    case Joi.validate_static(schema) do
      :ok -> :ok
      {:error, reason} -> compile_error!(env, "codec schema is not static: #{reason}")
    end
  end

  defp validate_field_options!(field, opts, env) do
    case Keyword.get(opts, :as) do
      nil -> :ok
      value when is_binary(value) and value != "" -> :ok
      _value -> compile_error!(env, "codec #{inspect(field)} :as must be a nonempty string")
    end

    for key <- [:decode, :encode], value = Keyword.get(opts, key), not is_nil(value) do
      unless valid_callback?(value) do
        compile_error!(env, "codec #{inspect(field)} :#{key} must be a function name or MFA")
      end
    end

    unless Keyword.get(opts, :omit, false) in [false, nil] do
      compile_error!(env, "codec #{inspect(field)} :omit must be false or :nil")
    end

    opts
  end

  defp valid_callback?(value) when is_atom(value), do: true
  defp valid_callback?({module, function}) when is_atom(module) and is_atom(function), do: true

  defp valid_callback?({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: true

  defp valid_callback?(_value), do: false

  defp compile_plan!(schema, field_options, env) do
    plan = compile_plan(schema, env)
    put_root_options!(plan, field_options, env)
  end

  defp compile_plan(schema, env) do
    case Schema.kind(schema) do
      :struct ->
        {:ok, module} = Schema.struct_module(schema)
        {:ok, fields} = Schema.fields(schema)

        {:struct, module, compile_fields(fields || [], env), Schema.unknown_keys(schema)}

      :map ->
        {:ok, fields} = Schema.fields(schema)

        if is_list(fields) do
          {:object, compile_fields(fields, env), Schema.unknown_keys(schema)}
        else
          {:ok, key_schema, value_schema} = Schema.map_types(schema)
          {:map, compile_optional_plan(key_schema, env), compile_optional_plan(value_schema, env)}
        end

      :array ->
        {:ok, inner} = Schema.inner(schema)
        {:array, compile_plan(inner, env)}

      :enum ->
        {:ok, type, values} = Schema.enum(schema)
        {:enum, type, values}

      :union ->
        {:ok, branches} = Schema.branches(schema)
        {:union, Enum.map(branches, &{&1, compile_plan(&1, env)})}

      :literal ->
        {:ok, value} = Schema.literal(schema)
        {:literal, value}

      :atom ->
        :atom

      :lazy ->
        compile_error!(env, "lazy Joi schemas cannot be compiled into JSON codecs")

      _kind ->
        :value
    end
  end

  defp compile_optional_plan(nil, _env), do: :value
  defp compile_optional_plan(schema, env), do: compile_plan(schema, env)

  defp compile_fields(fields, env) do
    Enum.map(fields, fn {field, schema} ->
      {field, default_json_key(field), compile_plan(schema, env), []}
    end)
  end

  defp put_root_options!(plan, field_options, env) do
    case plan do
      {kind, module, fields, unknown} when kind == :struct ->
        {kind, module, decorate_fields!(fields, field_options, env), unknown}

      {:object, fields, unknown} ->
        {:object, decorate_fields!(fields, field_options, env), unknown}

      _plan when map_size(field_options) == 0 ->
        plan

      _plan ->
        compile_error!(env, "codec field options require a field-based schema")
    end
  end

  defp decorate_fields!(fields, options, env) do
    known = MapSet.new(fields, &elem(&1, 0))

    case Enum.reject(Map.keys(options), &MapSet.member?(known, &1)) do
      [] -> :ok
      unknown -> compile_error!(env, "codec options name unknown fields: #{inspect(unknown)}")
    end

    decorated =
      Enum.map(fields, fn {field, default_key, plan, []} ->
        opts = Map.get(options, field, [])
        {field, Keyword.get(opts, :as, default_key), plan, opts}
      end)

    keys = Enum.map(decorated, &elem(&1, 1))

    if length(keys) != length(Enum.uniq(keys)) do
      compile_error!(env, "codec fields must have unique JSON names")
    end

    decorated
  end

  defp default_json_key(field) when is_atom(field), do: Atom.to_string(field)
  defp default_json_key(field) when is_binary(field), do: field

  defp encoder_ast(schema, module, env) do
    case Schema.struct_module(schema) do
      {:ok, ^module} ->
        quote do
          defimpl JSON.Encoder, for: unquote(module) do
            def encode(value, encoder) do
              value
              |> unquote(module).dump()
              |> JSON.Encoder.Map.encode(encoder)
            end
          end
        end

      {:ok, other} ->
        compile_error!(env, "struct codec schema belongs to #{inspect(other)}, not #{inspect(module)}")

      :error ->
        nil
    end
  end

  defp decode_value(value, {:struct, module, fields, unknown}, owner, path)
       when is_map(value) and not is_struct(value) do
    if module != owner and codec_module?(module) do
      prefix_result(module.from_map(value), path)
    else
      with {:ok, attrs} <- decode_fields(value, fields, unknown, owner, path) do
        {:ok, struct(module, attrs)}
      end
    end
  end

  defp decode_value(value, {:object, fields, unknown}, owner, path)
       when is_map(value) and not is_struct(value),
       do: decode_fields(value, fields, unknown, owner, path)

  defp decode_value(value, {:map, key_plan, value_plan}, owner, path)
       when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, child}, {:ok, decoded} ->
      with {:ok, decoded_key} <- decode_value(key, key_plan, owner, path ++ [key]),
           {:ok, decoded_value} <- decode_value(child, value_plan, owner, path ++ [key]) do
        {:cont, {:ok, Map.put(decoded, decoded_key, decoded_value)}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decode_value(value, {:array, inner}, owner, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {child, index}, {:ok, decoded} ->
      case decode_value(child, inner, owner, path ++ [index]) do
        {:ok, value} -> {:cont, {:ok, [value | decoded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> reverse_result()
  end

  defp decode_value(value, {:enum, :atom, values}, _owner, _path) when is_binary(value) do
    case Enum.find_value(values, fn {wire_value, parsed_value} ->
           if Atom.to_string(wire_value) == value, do: {:found, parsed_value}
         end) do
      {:found, atom} -> {:ok, atom}
      nil -> {:ok, value}
    end
  end

  defp decode_value(value, {:enum, _type, _values}, _owner, _path), do: {:ok, value}

  defp decode_value(value, :atom, _owner, _path) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:ok, value}
  end

  defp decode_value(value, {:literal, atom}, _owner, _path)
       when is_atom(atom) and is_binary(value) do
    if Atom.to_string(atom) == value, do: {:ok, atom}, else: {:ok, value}
  end

  defp decode_value(value, {:literal, _literal}, _owner, _path), do: {:ok, value}

  defp decode_value(value, {:union, branches}, owner, path) do
    Enum.find_value(branches, {:ok, value}, fn {schema, plan} ->
      with {:ok, decoded} <- decode_value(value, plan, owner, path),
           {:ok, _validated} <- Joi.parse(schema, decoded) do
        {:ok, decoded}
      else
        _error -> false
      end
    end)
  end

  defp decode_value(value, _plan, _owner, _path), do: {:ok, value}

  defp decode_fields(value, fields, unknown, owner, path) do
    json_keys = MapSet.new(fields, &elem(&1, 1))

    with :ok <- check_unknown_keys(value, json_keys, unknown, path) do
      initial = if unknown == :preserve, do: Map.drop(value, MapSet.to_list(json_keys)), else: %{}

      Enum.reduce_while(fields, {:ok, initial}, fn {field, json_key, plan, opts}, {:ok, acc} ->
        case Map.fetch(value, json_key) do
          {:ok, raw} ->
            case decode_value(raw, plan, owner, path ++ [json_key]) do
              {:ok, decoded} ->
                decoded = run_callback(decoded, Keyword.get(opts, :decode), owner)
                {:cont, {:ok, Map.put(acc, field, decoded)}}

              {:error, _reason} = error ->
                {:halt, error}
            end

          :error ->
            {:cont, {:ok, acc}}
        end
      end)
    end
  end

  defp check_unknown_keys(_value, _json_keys, mode, _path) when mode != :error, do: :ok

  defp check_unknown_keys(value, json_keys, :error, path) do
    case Enum.find(Map.keys(value), &(not MapSet.member?(json_keys, &1))) do
      nil -> :ok
      key -> {:error, [Joi.unrecognized_key_issue(key) |> Map.put(:path, path ++ [key])]}
    end
  end

  defp encode_value(value, {:struct, module, fields, _unknown}, owner)
       when is_struct(value, module) do
    if module != owner and codec_module?(module),
      do: module.dump(value),
      else: encode_fields(value, fields, owner)
  end

  defp encode_value(value, {:object, fields, unknown}, owner) when is_map(value) do
    encoded = encode_fields(value, fields, owner)

    if unknown == :preserve do
      known = MapSet.new(fields, &elem(&1, 0))

      Enum.reduce(value, encoded, fn {key, child}, acc ->
        if MapSet.member?(known, key),
          do: acc,
          else: Map.put(acc, encode_map_key(key), encode_value(child, :value, owner))
      end)
    else
      encoded
    end
  end

  defp encode_value(value, {:map, key_plan, value_plan}, owner) when is_map(value) do
    Map.new(value, fn {key, child} ->
      encoded_key = key |> encode_value(key_plan, owner) |> encode_map_key()
      {encoded_key, encode_value(child, value_plan, owner)}
    end)
  end

  defp encode_value(value, {:array, inner}, owner) when is_list(value),
    do: Enum.map(value, &encode_value(&1, inner, owner))

  defp encode_value(value, {:enum, :atom, values}, _owner) when is_atom(value) do
    case Enum.find(values, fn {_wire_value, parsed_value} -> parsed_value == value end) do
      {wire_value, ^value} -> Atom.to_string(wire_value)
      nil -> Atom.to_string(value)
    end
  end

  defp encode_value(value, :atom, _owner) when is_atom(value), do: Atom.to_string(value)

  defp encode_value(value, {:literal, literal}, _owner)
       when is_atom(literal) and value == literal,
       do: Atom.to_string(value)

  defp encode_value(value, {:union, branches}, owner) do
    case Enum.find(branches, fn {schema, _plan} -> match?({:ok, _}, Joi.parse(schema, value)) end) do
      {_schema, plan} -> encode_value(value, plan, owner)
      nil -> value
    end
  end

  defp encode_value(%module{} = value, :value, _owner) do
    if codec_module?(module), do: module.dump(value), else: value
  end

  defp encode_value(value, _plan, _owner), do: value

  defp encode_fields(value, fields, owner) do
    Enum.reduce(fields, %{}, fn {field, json_key, plan, opts}, acc ->
      case fetch_field(value, field) do
        {:ok, nil} ->
          if Keyword.get(opts, :omit, false) == nil,
            do: acc,
            else: Map.put(acc, json_key, nil)

        {:ok, child} ->
          child = run_callback(child, Keyword.get(opts, :encode), owner)
          Map.put(acc, json_key, encode_value(child, plan, owner))

        :error ->
          acc
      end
    end)
  end

  defp fetch_field(value, field) when is_map(value), do: Map.fetch(value, field)

  defp run_callback(value, nil, _owner), do: value
  defp run_callback(value, function, owner) when is_atom(function), do: apply(owner, function, [value])
  defp run_callback(value, {module, function}, _owner), do: apply(module, function, [value])

  defp run_callback(value, {module, function, args}, _owner),
    do: apply(module, function, [value | args])

  defp codec_module?(module),
    do: function_exported?(module, :__jido_codec__, 0) and module.__jido_codec__() == true

  defp prefix_result({:ok, value}, _path), do: {:ok, value}

  defp prefix_result({:error, errors}, path) when is_list(errors),
    do: {:error, Enum.map(errors, &Map.update(&1, :path, path, fn child -> path ++ child end))}

  defp prefix_result({:error, error}, _path), do: {:error, error}

  defp reverse_result({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_result({:error, _reason} = error), do: error

  defp encode_map_key(key) when is_binary(key), do: key
  defp encode_map_key(key) when is_atom(key), do: Atom.to_string(key)
  defp encode_map_key(key), do: to_string(key)

  defp compile_error!(env, description) do
    raise CompileError,
      file: env.file,
      line: env.line,
      description: description
  end
end
