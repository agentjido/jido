defmodule Jido.Authoring.Config do
  @moduledoc false

  alias Jido.Action.Validation
  alias Jido.Authoring.Registry
  alias Jido.Flow.Error

  @keys [:name, :description, :schema, :output_schema]
  @module_keys [:id, :vsn | @keys]
  @max_action_name_bytes 256

  @doc false
  @spec validate_name(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_name(name, _opts \\ [])

  def validate_name(name, _opts) when is_binary(name) do
    cond do
      not String.valid?(name) ->
        {:error, "Action name must be valid UTF-8."}

      String.trim(name) == "" ->
        {:error, "Action name cannot be blank."}

      byte_size(name) > @max_action_name_bytes ->
        {:error, "Action name cannot exceed #{@max_action_name_bytes} bytes."}

      true ->
        :ok
    end
  end

  def validate_name(_name, _opts) do
    {:error, "Action name must be a string."}
  end

  @doc false
  @spec validate_config_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_config_schema(value, _opts \\ [])

  def validate_config_schema(value, _opts) do
    if Validation.zoi_schema?(value) do
      :ok
    else
      {:error, "must be a Zoi schema"}
    end
  end

  @doc false
  @spec validate_map_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_map_schema(value, opts \\ []) do
    with :ok <- validate_config_schema(value, opts) do
      if Validation.map_schema?(value) do
        :ok
      else
        {:error, "must accept map-shaped data"}
      end
    end
  end

  @doc false
  @spec validate_static_data(term()) ::
          :ok | {:error, Jido.Authoring.Error.InvalidError.t()}
  def validate_static_data(term), do: Jido.Authoring.validate_static(term)

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

  @doc false
  @spec prepare!(Jido.Instruction.kind(), term(), Macro.Env.t()) ::
          map() | no_return()
  def prepare!(kind, raw_opts, env) do
    opts =
      raw_opts
      |> normalize_options()
      |> module_defaults(env.module)

    case validate_config(kind, opts, @module_keys) do
      {:ok, opts} ->
        ensure_escapable_schema!(opts.schema, :schema, env)
        ensure_escapable_schema!(opts.output_schema, :output_schema, env)
        opts

      {:error, errors} ->
        raise CompileError,
          description: compile_error(kind, errors),
          file: env.file,
          line: env.line
    end
  end

  @doc false
  @spec validate_flow(term()) :: {:ok, map()} | {:error, Exception.t()}
  def validate_flow(attrs) do
    case validate_config(:flow, attrs) do
      {:ok, opts} -> {:ok, opts}
      {:error, [error | _]} -> {:error, flow_error(error)}
    end
  end

  defp validate_config(kind, attrs), do: validate_config(kind, attrs, @keys)

  defp validate_config(kind, %{} = attrs, keys) when not is_struct(attrs) do
    {values, errors} =
      Enum.reduce(keys, {%{}, []}, fn field, {values, errors} ->
        case {kind, field, Map.fetch(attrs, field)} do
          {:action, :description, :error} ->
            {values, errors}

          {:action, :name, :error} ->
            {values, errors ++ [{field, :required}]}

          _ ->
            case validate_field(kind, field, Map.get(attrs, field)) do
              {:ok, value} -> {Map.put(values, field, value), errors}
              {:error, reason} -> {values, errors ++ [{field, reason}]}
            end
        end
      end)

    unknown = for key <- Map.keys(attrs), key not in keys, do: {nil, {:unknown, key}}
    errors = if kind == :action, do: errors ++ unknown, else: unknown ++ errors

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  defp validate_config(_kind, _attrs, _keys), do: {:error, [{nil, :map}]}

  defp validate_field(_kind, :id, value) when is_binary(value) do
    case Registry.validate_identifier(value) do
      :ok -> {:ok, value}
      {:error, _error} -> {:error, "must be a valid authoring identifier"}
    end
  end

  defp validate_field(_kind, :id, _value),
    do: {:error, "must be a valid authoring identifier"}

  defp validate_field(_kind, :vsn, value) do
    case Registry.validate_vsn(value) do
      :ok -> {:ok, value}
      {:error, _error} -> {:error, "must be a positive integer"}
    end
  end

  defp validate_field(_kind, :name, value) when is_binary(value) do
    case validate_name(value) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_field(:flow, :description, nil), do: {:ok, nil}

  defp validate_field(kind, :description, value) when is_binary(value) do
    if kind == :flow and not String.valid?(value),
      do: {:error, "flow description must be valid UTF-8"},
      else: {:ok, value}
  end

  defp validate_field(_kind, field, _value) when field in [:name, :description],
    do: {:error, :string}

  defp validate_field(_kind, field, nil)
       when field in [:schema, "schema", :output_schema, "output_schema"],
       do: {:ok, Zoi.map()}

  defp validate_field(_kind, _field, nil), do: {:ok, []}

  defp validate_field(_kind, _field, value) do
    with :ok <- static_schema(value),
         :ok <- validate_map_schema(value) do
      {:ok, value}
    end
  end

  @doc false
  @spec flow_name(term()) :: {:ok, String.t()} | {:error, Exception.t()}
  def flow_name(value), do: flow_field(:name, value)

  @doc false
  @spec description(term()) :: {:ok, String.t() | nil} | {:error, Exception.t()}
  def description(value), do: flow_field(:description, value)

  @doc false
  @spec schema(term(), String.t()) :: {:ok, Jido.Action.schema()} | {:error, Exception.t()}
  def schema(value, field), do: flow_field(field, value)

  defp flow_field(field, value) do
    case validate_field(:flow, field, value) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, flow_error({field, reason})}
    end
  end

  defp static_schema(value) do
    case validate_static_data(value) do
      :ok -> :ok
      {:error, error} -> {:error, {:static, Exception.message(error)}}
    end
  end

  defp compile_error(:flow, [error | _]),
    do: "Flow configuration validation failed: #{Exception.message(flow_error(error))}"

  defp compile_error(:action, errors) do
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

  defp flow_error({nil, {:unknown, key}}),
    do: Error.validation_error("unknown Flow configuration key: #{inspect(key)}", %{key: key})

  defp flow_error({nil, :map}), do: Error.validation_error("flow configuration must be a map")
  defp flow_error({field, :string}), do: Error.validation_error("flow #{field} must be a string")

  defp flow_error({field, {:static, reason}}),
    do: flow_error({field, "must be static module data; #{reason}"})

  defp flow_error({field, reason}) when field in [:name, :description],
    do: Error.validation_error(reason)

  defp flow_error({field, reason}),
    do: Error.validation_error("#{field} #{reason}", %{field: to_string(field)})

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
