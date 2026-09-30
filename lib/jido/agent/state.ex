defmodule Jido.Agent.State do
  @moduledoc false

  alias Jido.Error
  alias Jido.Util.DeepMerge

  @doc false
  def defaults_from_schema(%Zoi.Types.Map{fields: fields}) do
    Enum.reduce(fields, %{}, fn
      {key, %Zoi.Types.Default{value: value, meta: %{required: required}}}, defaults
      when required != false ->
        Map.put(defaults, key, value)

      {_key, _field_schema}, defaults ->
        defaults
    end)
  end

  @doc false
  def initialize(state, schema) when is_map(state) and not is_struct(state) do
    initial = schema |> defaults_from_schema() |> DeepMerge.merge(state)

    schema = %{schema | unrecognized_keys: :error}
    state_result(Zoi.parse(schema, initial, parse_defaults: true, immutable_refinements: true))
  end

  def initialize(state, _schema) do
    {:error,
     Error.validation_error("Agent instance state must be a map",
       kind: :config,
       details: %{state: state}
     )}
  end

  @spec validate_schema(term()) :: :ok | {:error, Error.ValidationError.t()}
  def validate_schema(%Zoi.Types.Map{fields: fields} = schema) when is_list(fields),
    do: validate_state_schema(schema)

  def validate_schema(schema) do
    {:error,
     Error.validation_error("Agent schema must be a field-based Zoi object",
       field: :schema,
       details: %{schema: schema}
     )}
  end

  @spec validate(term(), Zoi.schema()) :: {:ok, map()} | {:error, Error.ValidationError.t()}
  def validate(state, %Zoi.Types.Map{} = schema)
      when is_map(state) and not is_struct(state) do
    schema = %{schema | unrecognized_keys: :error}

    case Zoi.validate(schema, state) do
      :ok -> {:ok, state}
      {:error, errors} -> state_result({:error, errors})
    end
  end

  def validate(state, _schema) do
    {:error,
     Error.validation_error("Agent state must be a map",
       field: :state,
       details: %{state: state}
     )}
  end

  @doc false
  @spec validate_candidate(term(), Zoi.schema()) ::
          {:ok, map()} | {:error, Error.ValidationError.t()}
  def validate_candidate(state, %Zoi.Types.Map{} = schema)
      when is_map(state) and not is_struct(state) do
    missing_keys =
      for {key, %Zoi.Types.Default{meta: %{required: required}}} <- schema.fields,
          required != false,
          not Map.has_key?(state, key),
          do: key

    missing_keys = Enum.sort(missing_keys)

    if missing_keys == [] do
      validate(state, schema)
    else
      {:error,
       Error.validation_error("Agent candidate state omits defaulted fields",
         field: :state,
         details: %{missing_keys: missing_keys}
       )}
    end
  end

  def validate_candidate(state, schema), do: validate(state, schema)

  defp state_result({:ok, state}), do: {:ok, state}

  defp state_result({:error, errors}) do
    {:error,
     Error.validation_error("Agent state does not match its schema",
       field: :state,
       details: %{errors: errors}
     )}
  end

  defp validate_state_schema(schema) do
    with :ok <- static_schema(schema), do: validation_only_schema(schema)
  end

  defp validation_only_schema(%{__struct__: type, meta: %Zoi.Types.Meta{} = meta} = schema) do
    cond do
      Enum.any?(meta.effects, &match?({:transform, _}, &1)) ->
        schema_policy_error(:transform, type)

      Map.get(schema, :coerce) == true ->
        schema_policy_error(:coercion, type)

      type in [Zoi.Types.Codec, Zoi.Types.Lazy, Zoi.Types.StringBoolean] ->
        schema_policy_error(:input_conversion, type)

      true ->
        schema
        |> Map.take([:inner, :fields, :schemas, :key_type, :value_type, :unrecognized_keys])
        |> Map.values()
        |> validation_only_schema()
    end
  end

  defp validation_only_schema(values) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validation_only_schema(value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validation_only_schema(values) when is_tuple(values),
    do: values |> Tuple.to_list() |> validation_only_schema()

  defp validation_only_schema(values) when is_map(values),
    do: values |> Map.values() |> validation_only_schema()

  defp validation_only_schema(_value), do: :ok

  defp schema_policy_error(reason, type) do
    {:error,
     Error.validation_error("Agent state schemas must contain only defaults and validation rules",
       field: :schema,
       details: %{reason: reason, schema_type: type}
     )}
  end

  defp static_schema(schema) do
    case Jido.Action.validate_static_data(schema) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.validation_error("Agent schema must contain static data",
           field: :schema,
           details: %{reason: reason}
         )}
    end
  end
end
