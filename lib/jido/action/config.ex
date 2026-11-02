defmodule Jido.Action.Config do
  @moduledoc false

  alias Jido.Authoring.Config, as: AuthoringConfig
  alias Jido.Authoring.Registry

  @module_keys [:id, :vsn, :name, :description, :schema, :output_schema]

  @doc false
  @spec prepare!(term(), Macro.Env.t()) :: map() | no_return()
  def prepare!(raw_opts, env) do
    opts =
      raw_opts
      |> normalize_options()
      |> module_defaults(env.module)

    case validate_config(opts, @module_keys) do
      {:ok, opts} ->
        ensure_escapable_schema!(opts.schema, :schema, env)
        ensure_escapable_schema!(opts.output_schema, :output_schema, env)
        opts

      {:error, errors} ->
        raise CompileError,
          description: compile_error(errors),
          file: env.file,
          line: env.line
    end
  end

  defp ensure_escapable_schema!(schema, option, env) do
    Macro.escape(schema)
    schema
  rescue
    ArgumentError ->
      raise CompileError,
        description:
          "#{inspect(option)} must be static module data that can be stored in the Action module. " <>
            "Use named MFA effects such as {Module, :function, args}",
        file: env.file,
        line: env.line
  end

  defp validate_config(%{} = attrs, keys) when not is_struct(attrs) do
    {values, errors} =
      Enum.reduce(keys, {%{}, []}, fn field, {values, errors} ->
        case {field, Map.fetch(attrs, field)} do
          {:description, :error} ->
            {values, errors}

          {:name, :error} ->
            {values, errors ++ [{field, :required}]}

          _ ->
            case validate_field(field, Map.get(attrs, field)) do
              {:ok, value} -> {Map.put(values, field, value), errors}
              {:error, reason} -> {values, errors ++ [{field, reason}]}
            end
        end
      end)

    unknown = for key <- Map.keys(attrs), key not in keys, do: {nil, {:unknown, key}}
    errors = errors ++ unknown

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  defp validate_config(_attrs, _keys), do: {:error, [{nil, :map}]}

  defp validate_field(:id, value) when is_binary(value) do
    case Registry.validate_identifier(value) do
      :ok -> {:ok, value}
      {:error, _error} -> {:error, "must be a valid authoring identifier"}
    end
  end

  defp validate_field(:id, _value),
    do: {:error, "must be a valid authoring identifier"}

  defp validate_field(:vsn, value) do
    case Registry.validate_vsn(value) do
      :ok -> {:ok, value}
      {:error, _error} -> {:error, "must be a positive integer"}
    end
  end

  defp validate_field(:name, value) when is_binary(value) do
    case AuthoringConfig.validate_name(value, subject: "Action") do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_field(:description, value) when is_binary(value), do: {:ok, value}

  defp validate_field(field, _value) when field in [:name, :description],
    do: {:error, :string}

  defp validate_field(_field, nil), do: {:ok, []}

  defp validate_field(_field, value) do
    with :ok <- static_schema(value),
         :ok <- AuthoringConfig.validate_map_schema(value) do
      {:ok, value}
    end
  end

  defp static_schema(value) do
    case AuthoringConfig.validate_static_data(value) do
      :ok -> :ok
      {:error, error} -> {:error, {:static, Exception.message(error)}}
    end
  end

  defp compile_error(errors) do
    case Enum.find(errors, fn {_field, reason} -> match?({:static, _}, reason) end) do
      {field, {:static, reason}} ->
        "#{inspect(field)} must be static module data; #{reason}. " <>
          "Use named MFA effects such as {Module, :function, args}"

      nil ->
        "Action configuration validation failed:\n" <>
          Enum.map_join(errors, "\n", &action_error/1)
    end
  end

  defp action_error({nil, {:unknown, key}}), do: Zoi.Error.unrecognized_key(key).message
  defp action_error({nil, :map}), do: "invalid type: expected map"
  defp action_error({field, :required}), do: "is required, at #{field}"
  defp action_error({field, :string}), do: "invalid type: expected string, at #{field}"
  defp action_error({field, reason}), do: "#{reason}, at #{field}"

  defp normalize_options(raw_opts) when is_list(raw_opts) do
    if Keyword.keyword?(raw_opts), do: Map.new(raw_opts), else: raw_opts
  end

  defp normalize_options(raw_opts), do: raw_opts

  defp module_defaults(%{} = opts, module) when not is_struct(opts) do
    opts
    |> Map.put_new(:id, Atom.to_string(module))
    |> Map.put_new(:vsn, 1)
  end

  defp module_defaults(opts, _module), do: opts
end
