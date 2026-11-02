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

  def kind?(schema, expected), do: kind(schema) == expected

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

  def put_fields(%Zoi.Types.Map{} = schema, fields), do: %{schema | fields: fields}
  def put_fields(%Zoi.Types.Struct{} = schema, fields), do: %{schema | fields: fields}
  def put_fields(%Zoi.Types.Keyword{} = schema, fields), do: %{schema | fields: fields}

  def put_unrecognized_keys(%Zoi.Types.Map{} = schema, value),
    do: %{schema | unrecognized_keys: value}

  def put_unrecognized_keys(%Zoi.Types.Struct{} = schema, value),
    do: %{schema | unrecognized_keys: value}

  def put_unrecognized_keys(%Zoi.Types.Keyword{} = schema, value),
    do: %{schema | unrecognized_keys: value}

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

  def literal(%Zoi.Types.Literal{value: value}), do: {:ok, value}
  def literal(_), do: :error

  def struct_module(%Zoi.Types.Struct{module: module}), do: {:ok, module}
  def struct_module(_), do: :error

  def coerce?(schema), do: Map.get(schema, :coerce, false)
  def without_coercion(%{coerce: _coerce} = schema), do: %{schema | coerce: false}
  def without_coercion(schema), do: schema
  def empty_values(schema), do: Map.get(schema, :empty_values, [])
  def unrecognized_keys(schema), do: Map.get(schema, :unrecognized_keys)

  def effects(%Zoi.Types.Meta{effects: effects}), do: effects
  def effects(%{meta: %Zoi.Types.Meta{effects: effects}}), do: effects
  def effects(_), do: []

  def effect_modules(schema) do
    schema
    |> effects()
    |> Enum.flat_map(fn
      {_kind, {module, _function, _args}} when is_atom(module) -> [module]
      _ -> []
    end)
  end

  def resolve_lazy(%Zoi.Types.Lazy{fun: {module, function, args}}),
    do: apply(module, function, args)

  def resolve_lazy(%Zoi.Types.Lazy{fun: fun}), do: fun.()
  def resolve_lazy(schema), do: schema

  def traverse(schema, fun), do: Zoi.Schema.traverse(schema, fun)

  def type_module(schema) when is_struct(schema), do: schema.__struct__
  def type_module(_), do: nil

  def forbidden_state_type?(schema), do: kind(schema) in [:codec, :lazy, :string_boolean]

  def transform_effect?({:transform, _}), do: true
  def transform_effect?(_), do: false
end
