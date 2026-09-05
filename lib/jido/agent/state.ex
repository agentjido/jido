defmodule Jido.Agent.State do
  @moduledoc false

  alias Jido.Error
  alias Jido.Util.DeepMerge

  @doc false
  def merge(current_state, attrs) when is_list(attrs), do: merge(current_state, Map.new(attrs))
  def merge(current_state, attrs) when is_map(attrs), do: DeepMerge.merge(current_state, attrs)

  @doc false
  def defaults_from_schema(%Zoi.Types.Map{fields: fields}) do
    Enum.reduce(fields, %{}, fn
      {key, %Zoi.Types.Default{} = field_schema}, defaults ->
        {:ok, value} = Zoi.parse(field_schema, nil)
        Map.put(defaults, key, value)

      {_key, _field_schema}, defaults ->
        defaults
    end)
  end

  @spec validate_schema(term()) :: :ok | {:error, Error.ValidationError.t()}
  def validate_schema(%Zoi.Types.Map{fields: fields} = schema) when is_list(fields) do
    with :ok <- static_schema(schema) do
      :ok
    end
  end

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

    case Zoi.parse(schema, state) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        {:error,
         Error.validation_error("Agent state does not match its schema",
           field: :state,
           details: %{errors: errors}
         )}
    end
  end

  def validate(state, _schema) do
    {:error,
     Error.validation_error("Agent state must be a map",
       field: :state,
       details: %{state: state}
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
