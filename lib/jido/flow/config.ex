defmodule Jido.Flow.Config do
  @moduledoc false

  alias Jido.Authoring.Config
  alias Jido.Flow.Error

  @keys [:name, :description, :schema, :output_schema]

  @doc false
  @spec validate(term()) :: {:ok, map()} | {:error, Exception.t()}
  def validate(attrs), do: validate_fields(attrs, @keys)

  @doc false
  @spec validate_name(term(), keyword()) :: :ok | {:error, String.t()}
  defdelegate validate_name(name, options \\ []), to: Config

  @doc false
  @spec schema(term(), String.t()) :: {:ok, Jido.Action.schema()} | {:error, Exception.t()}
  def schema(value, label) do
    case validate_schema(value) do
      {:ok, schema} -> {:ok, schema}
      {:error, reason} -> {:error, field_error(label, reason)}
    end
  end

  defp validate_fields(%{} = attrs, keys) when not is_struct(attrs) do
    unknown =
      attrs
      |> Map.keys()
      |> Enum.reject(&(&1 in keys))
      |> Enum.sort()
      |> Enum.map(&{nil, {:unknown, &1}})

    errors_and_values =
      Enum.reduce(keys, {unknown, %{}}, fn field, {errors, values} ->
        case validate_field(field, Map.get(attrs, field)) do
          {:ok, value} -> {errors, Map.put(values, field, value)}
          {:error, reason} -> {errors ++ [{field, reason}], values}
        end
      end)

    case errors_and_values do
      {[], values} -> {:ok, values}
      {[error | _rest], _values} -> {:error, flow_error(error)}
    end
  end

  defp validate_fields(_attrs, _keys),
    do: {:error, Error.validation_error("flow configuration must be a map")}

  defp validate_field(:name, value) when is_binary(value) do
    case Config.validate_name(value, subject: "Flow") do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_field(:name, _value), do: {:error, :string}
  defp validate_field(:description, nil), do: {:ok, nil}

  defp validate_field(:description, value) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value},
      else: {:error, "flow description must be valid UTF-8"}
  end

  defp validate_field(:description, _value), do: {:error, :string}

  defp validate_field(field, value) when field in [:schema, :output_schema],
    do: validate_schema(value)

  defp validate_schema(nil), do: {:ok, []}

  defp validate_schema(value) do
    with :ok <- static_schema(value),
         :ok <- Config.validate_map_schema(value) do
      {:ok, value}
    end
  end

  defp static_schema(value) do
    case Config.validate_static_data(value) do
      :ok -> :ok
      {:error, error} -> {:error, {:static, Exception.message(error)}}
    end
  end

  defp flow_error({nil, {:unknown, key}}),
    do: Error.validation_error("unknown Flow configuration key: #{inspect(key)}", %{key: key})

  defp flow_error({field, reason}), do: field_error(field, reason)

  defp field_error(field, :string),
    do: Error.validation_error("flow #{field} must be a string")

  defp field_error(field, {:static, reason}),
    do: field_error(field, "must be static module data; #{reason}")

  defp field_error(field, reason) when field in [:name, :description],
    do: Error.validation_error(reason)

  defp field_error(field, reason),
    do: Error.validation_error("#{field} #{reason}", %{field: to_string(field)})
end
