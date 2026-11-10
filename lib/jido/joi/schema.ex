defmodule Jido.Joi.Schema do
  @moduledoc false

  @type kind ::
          :any
          | :array
          | :atom
          | :codec
          | :discriminated_union
          | :enum
          | :integer
          | :intersection
          | :keyword
          | :lazy
          | :literal
          | :map
          | :meta
          | :string_boolean
          | :struct
          | :union
          | :other
          | :not_schema

  def schema?(value), do: is_struct(value) and not is_nil(Zoi.Type.impl_for(value))

  def kind(%Zoi.Types.Any{}), do: :any
  def kind(%Zoi.Types.Array{}), do: :array
  def kind(%Zoi.Types.Atom{}), do: :atom
  def kind(%Zoi.Types.Codec{}), do: :codec
  def kind(%Zoi.Types.DiscriminatedUnion{}), do: :discriminated_union
  def kind(%Zoi.Types.Enum{}), do: :enum
  def kind(%Zoi.Types.Integer{}), do: :integer
  def kind(%Zoi.Types.Intersection{}), do: :intersection
  def kind(%Zoi.Types.Keyword{}), do: :keyword
  def kind(%Zoi.Types.Lazy{}), do: :lazy
  def kind(%Zoi.Types.Literal{}), do: :literal
  def kind(%Zoi.Types.Map{}), do: :map
  def kind(%Zoi.Types.Meta{}), do: :meta
  def kind(%Zoi.Types.StringBoolean{}), do: :string_boolean
  def kind(%Zoi.Types.Struct{}), do: :struct
  def kind(%Zoi.Types.Union{}), do: :union
  def kind(value), do: if(schema?(value), do: :other, else: :not_schema)

  def map_shaped?(%Zoi.Types.Map{}), do: true
  def map_shaped?(%Zoi.Types.Struct{}), do: true
  def map_shaped?(%Zoi.Types.Any{}), do: true
  def map_shaped?(%Zoi.Types.DiscriminatedUnion{}), do: true

  def map_shaped?(%Zoi.Types.Lazy{} = schema) do
    case resolve_lazy(schema) do
      %Zoi.Types.Lazy{} -> false
      resolved -> map_shaped?(resolved)
    end
  rescue
    _ -> false
  end

  def map_shaped?(%Zoi.Types.Literal{value: value}), do: is_map(value)

  def map_shaped?(%Zoi.Types.Union{schemas: schemas}),
    do: Enum.any?(schemas, &map_shaped?/1)

  def map_shaped?(%Zoi.Types.Intersection{schemas: schemas}),
    do: Enum.all?(schemas, &map_shaped?/1)

  def map_shaped?(%Zoi.Types.Codec{from: from, to: to}),
    do: map_shaped?(from) and map_shaped?(to)

  def map_shaped?(_), do: false

  def fields(%Zoi.Types.Map{fields: fields}), do: {:ok, fields}
  def fields(%Zoi.Types.Struct{fields: fields}), do: {:ok, fields}
  def fields(%Zoi.Types.Keyword{fields: fields}), do: {:ok, fields}
  def fields(_), do: :error

  def map_types(%Zoi.Types.Map{key_type: key_type, value_type: value_type}),
    do: {:ok, key_type, value_type}

  def map_types(_), do: :error

  def unknown_keys(%{unrecognized_keys: mode}), do: mode
  def unknown_keys(_), do: :error

  def literal(%Zoi.Types.Literal{value: value}), do: {:ok, value}
  def literal(_), do: :error

  def put_fields(%Zoi.Types.Map{} = schema, fields), do: %{schema | fields: fields}
  def put_fields(%Zoi.Types.Struct{} = schema, fields), do: %{schema | fields: fields}
  def put_fields(%Zoi.Types.Keyword{} = schema, fields), do: %{schema | fields: fields}

  def inner(%Zoi.Types.Array{inner: inner}), do: {:ok, inner}
  def inner(%Zoi.Types.Codec{to: inner}), do: {:ok, inner}
  def inner(_), do: :error

  def put_inner(%Zoi.Types.Array{} = schema, inner), do: %{schema | inner: inner}

  def branches(%Zoi.Types.Union{schemas: schemas}), do: {:ok, schemas}
  def branches(%Zoi.Types.Intersection{schemas: schemas}), do: {:ok, schemas}
  def branches(%Zoi.Types.DiscriminatedUnion{schemas: schemas}), do: {:ok, schemas}
  def branches(_), do: :error

  def enum(%Zoi.Types.Enum{enum_type: type, values: values}), do: {:ok, type, values}
  def enum(_), do: :error

  def struct_module(%Zoi.Types.Struct{module: module}), do: {:ok, module}
  def struct_module(_), do: :error

  def coerce?(schema), do: Map.get(schema, :coerce, false)

  def effects(%Zoi.Types.Meta{effects: effects}), do: effects
  def effects(%{meta: %Zoi.Types.Meta{effects: effects}}), do: effects
  def effects(_), do: []

  def forbidden_state_type?(schema), do: kind(schema) in [:codec, :lazy, :string_boolean]

  def transform_effect?({:transform, _}), do: true
  def transform_effect?(_), do: false

  def validate_stored(schema) do
    if schema?(schema),
      do: validate_stored_value(schema, []),
      else: stored_error("expected a Joi schema", [])
  end

  def close(schema), do: rewrite_unknown_keys(schema, :error)

  @doc false
  def validate_closed_fields(value, allowed, _opts) when is_map(value) do
    case Map.keys(value) -- allowed do
      [] -> :ok
      [key | _rest] -> {:error, Zoi.Error.unrecognized_key(key)}
    end
  end

  defp validate_stored_value(%_{} = value, path) do
    if schema?(value) do
      cond do
        coerce?(value) ->
          stored_error("stored schemas cannot coerce values", path)

        forbidden_state_type?(value) ->
          stored_error("stored schemas cannot use conversion or dynamic types", path)

        Enum.any?(effects(value), &transform_effect?/1) ->
          stored_error("stored schemas cannot transform values", path)

        Map.get(value, :unrecognized_keys) == :strip ->
          stored_error("stored schemas cannot strip undeclared fields", path)

        Map.get(value, :prefix_items, []) != [] ->
          stored_error("stored schemas do not support array prefix items", path)

        Map.get(value, :pattern_properties, []) != [] ->
          stored_error("stored schemas do not support map pattern properties", path)

        true ->
          value |> Map.from_struct() |> validate_stored_value(path)
      end
    else
      value |> Map.from_struct() |> validate_stored_value(path)
    end
  end

  defp validate_stored_value(value, path) when is_map(value) do
    Enum.reduce_while(value, :ok, fn {key, child}, :ok ->
      case validate_stored_value(child, path ++ [key]) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_stored_value(value, path) when is_list(value),
    do: validate_stored_list(value, path, 0)

  defp validate_stored_value(value, path) when is_tuple(value),
    do: value |> Tuple.to_list() |> validate_stored_list(path, 0)

  defp validate_stored_value(_value, _path), do: :ok

  defp validate_stored_list([], _path, _index), do: :ok

  defp validate_stored_list([value | rest], path, index) when is_list(rest) do
    with :ok <- validate_stored_value(value, path ++ [index]),
         do: validate_stored_list(rest, path, index + 1)
  end

  defp validate_stored_list(_improper, path, index),
    do: stored_error("stored schemas cannot contain improper lists", path ++ [index])

  defp rewrite_unknown_keys(%Zoi.Types.Intersection{schemas: schemas} = intersection, :error) do
    if Enum.all?(schemas, &field_map?/1) do
      allowed = schemas |> Enum.flat_map(&field_keys/1) |> Enum.uniq()

      schemas =
        Enum.map(schemas, fn schema ->
          schema = rewrite_unknown_keys(schema, :error)
          %{schema | unrecognized_keys: :preserve}
        end)

      effect = {:refine, {__MODULE__, :validate_closed_fields, [allowed]}}
      meta = %{intersection.meta | effects: intersection.meta.effects ++ [effect]}
      %{intersection | schemas: schemas, meta: meta}
    else
      rewrite_struct_unknown_keys(intersection, :error)
    end
  end

  defp rewrite_unknown_keys(%_{} = value, mode),
    do: rewrite_struct_unknown_keys(value, mode)

  defp rewrite_unknown_keys(value, mode) when is_map(value),
    do: Map.new(value, fn {key, child} -> {key, rewrite_unknown_keys(child, mode)} end)

  defp rewrite_unknown_keys(value, mode) when is_list(value),
    do: Enum.map(value, &rewrite_unknown_keys(&1, mode))

  defp rewrite_unknown_keys(value, mode) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&rewrite_unknown_keys(&1, mode))
    |> List.to_tuple()
  end

  defp rewrite_unknown_keys(value, _mode), do: value

  defp rewrite_struct_unknown_keys(value, mode) do
    fields =
      value
      |> Map.from_struct()
      |> Map.new(fn {key, child} -> {key, rewrite_unknown_keys(child, mode)} end)

    value
    |> then(&struct!(&1.__struct__, fields))
    |> put_unknown_keys_if_supported(mode)
  end

  defp put_unknown_keys_if_supported(%Zoi.Types.Map{} = schema, mode),
    do: %{schema | unrecognized_keys: mode}

  defp put_unknown_keys_if_supported(%Zoi.Types.Struct{} = schema, mode),
    do: %{schema | unrecognized_keys: mode}

  defp put_unknown_keys_if_supported(%Zoi.Types.Keyword{} = schema, mode),
    do: %{schema | unrecognized_keys: mode}

  defp put_unknown_keys_if_supported(schema, _mode), do: schema

  defp field_map?(%Zoi.Types.Map{fields: fields}), do: is_list(fields)
  defp field_map?(_schema), do: false

  defp field_keys(%Zoi.Types.Map{fields: fields}), do: Enum.map(fields, &elem(&1, 0))

  defp resolve_lazy(%Zoi.Types.Lazy{fun: {module, function, args}}),
    do: apply(module, function, args)

  defp resolve_lazy(%Zoi.Types.Lazy{fun: fun}), do: fun.()

  defp stored_error(reason, []), do: {:error, reason}
  defp stored_error(reason, path), do: {:error, "#{reason} at #{inspect(path)}"}
end
