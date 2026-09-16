defmodule Jido.Agent.State do
  @moduledoc false

  alias Jido.Error
  alias Jido.PortableTerm
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
  def validate_schema(%Zoi.Types.Map{fields: fields} = schema) when is_list(fields),
    do: static_schema(schema)

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
        with :ok <- validate_portable(validated), do: {:ok, validated}

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

  @doc false
  @spec validate_candidate(term(), Zoi.schema()) ::
          {:ok, map()} | {:error, Error.ValidationError.t()}
  def validate_candidate(state, %Zoi.Types.Map{} = schema)
      when is_map(state) and not is_struct(state) do
    missing_keys =
      schema
      |> defaults_from_schema()
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(state, &1))
      |> Enum.sort()

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

  defp validate_portable(state) do
    case PortableTerm.validate(state, :agent_state) do
      :ok ->
        :ok

      {:error, path} ->
        {:error,
         Error.validation_error("Agent state contains a non-portable term",
           field: :state,
           details: %{code: :non_portable_term, path: path}
         )}
    end
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
