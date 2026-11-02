defmodule Jido.Validation do
  @moduledoc false

  defmodule Error do
    @moduledoc false

    defexception message: "Validation failed", details: %{}

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  @doc false
  @spec open_validate(term(), term(), map()) :: {:ok, term()} | {:error, Error.t()}
  def open_validate([], data, _details), do: {:ok, data}

  def open_validate(schema, data, details) when is_map(details),
    do: validate_open(schema, data, details, &normalize_open_result/3)

  @doc false
  @spec open_validate_preserving_shape(term(), term(), map()) ::
          {:ok, term()} | {:error, Error.t()}
  def open_validate_preserving_shape([], data, _details), do: {:ok, data}

  def open_validate_preserving_shape(schema, data, details) when is_map(details),
    do: validate_open(schema, data, details, &preserve_open_result/3)

  @doc false
  @spec zoi_schema?(term()) :: boolean()
  def zoi_schema?(value), do: is_struct(value) && Zoi.Type.impl_for(value) != nil

  @doc false
  @spec map_schema?(term()) :: boolean()
  def map_schema?(%Zoi.Types.Map{}), do: true
  def map_schema?(%Zoi.Types.Struct{}), do: true
  def map_schema?(%Zoi.Types.Any{}), do: true
  def map_schema?(%Zoi.Types.DiscriminatedUnion{}), do: true

  def map_schema?(%Zoi.Types.Lazy{} = schema) do
    case resolve_lazy(schema) do
      %Zoi.Types.Lazy{} -> false
      resolved -> map_schema?(resolved)
    end
  rescue
    _exception -> false
  end

  def map_schema?(%Zoi.Types.Literal{value: value}), do: is_map(value)

  # Zoi 0.18.11 stores defaults in metadata and no longer defines this wrapper.
  def map_schema?(%{__struct__: Zoi.Types.Default, inner: inner}), do: map_schema?(inner)

  def map_schema?(%Zoi.Types.Union{schemas: schemas}),
    do: Enum.any?(schemas, &map_schema?/1)

  def map_schema?(%Zoi.Types.Intersection{schemas: schemas}),
    do: Enum.all?(schemas, &map_schema?/1)

  def map_schema?(%Zoi.Types.Codec{from: from, to: to}),
    do: map_schema?(from) and map_schema?(to)

  def map_schema?(_schema), do: false

  defp validate_open(schema, data, details, on_success) do
    if zoi_schema?(schema) do
      safely_validate(details, fn ->
        case parse_schema(schema, data) do
          {{:ok, validated}, unknown} -> on_success.(validated, unknown, schema)
          {{:error, errors}, _unknown} -> validation_error(errors, details)
        end
      end)
    else
      error("Unsupported schema type", details)
    end
  end

  defp safely_validate(details, validate) do
    validate.()
  rescue
    exception ->
      error(
        "schema validation failed",
        Map.merge(details, %{
          exception: exception.__struct__,
          reason: Exception.message(exception)
        })
      )
  catch
    kind, reason ->
      error(
        "schema validation failed",
        Map.merge(details, %{failure_kind: kind, reason: inspect(reason)})
      )
  end

  defp resolve_lazy(%Zoi.Types.Lazy{fun: {module, function, args}}),
    do: apply(module, function, args)

  defp resolve_lazy(%Zoi.Types.Lazy{fun: fun}), do: fun.()

  defp parse_schema(%Zoi.Types.Map{fields: fields} = schema, data)
       when is_list(fields) and is_map(data) do
    {Zoi.parse(open_root_object(schema), data), %{}}
  end

  defp parse_schema(
         %Zoi.Types.Struct{fields: fields, unrecognized_keys: :error} = schema,
         data
       )
       when is_list(fields) and is_map(data) do
    {Zoi.parse(schema, data), %{}}
  end

  defp parse_schema(%Zoi.Types.Struct{fields: fields} = schema, data)
       when is_list(fields) and is_map(data) do
    cond do
      is_struct(data, schema.module) ->
        {_known, unknown} = split_known_fields(Map.from_struct(data), fields, schema.coerce)
        {Zoi.parse(schema, data), unknown}

      schema.coerce ->
        data = if is_struct(data), do: Map.from_struct(data), else: data
        {known, unknown} = split_known_fields(data, fields, true)
        {Zoi.parse(schema, known), unknown}

      true ->
        {Zoi.parse(schema, data), %{}}
    end
  end

  defp parse_schema(schema, data), do: {Zoi.parse(schema, data), %{}}

  defp open_root_object(%Zoi.Types.Map{unrecognized_keys: :strip} = schema),
    do: %{schema | unrecognized_keys: :preserve}

  defp open_root_object(schema), do: schema

  defp split_known_fields(data, fields, false),
    do: Map.split(data, Enum.map(fields, &elem(&1, 0)))

  defp split_known_fields(data, fields, true) do
    known_keys = MapSet.new(fields, fn {key, _schema} -> to_string(key) end)
    keys = Enum.filter(Map.keys(data), &MapSet.member?(known_keys, to_string(&1)))
    Map.split(data, keys)
  end

  defp normalize_open_result(validated, unknown, schema) do
    validated = normalize_validated(schema, validated)

    if is_map(validated) and object_schema?(schema),
      do: {:ok, Map.merge(unknown, validated)},
      else: {:ok, validated}
  end

  defp preserve_open_result(validated, unknown, schema) do
    if is_map(validated) and not is_struct(validated) and object_schema?(schema),
      do: {:ok, Map.merge(unknown, validated)},
      else: {:ok, validated}
  end

  defp validation_error(errors, details) do
    error(
      Zoi.prettify_errors(errors),
      Map.put(details, :errors, Enum.map(errors, &format_zoi_error/1))
    )
  end

  defp object_schema?(%{__struct__: Zoi.Types.Map}), do: true
  defp object_schema?(%{__struct__: Zoi.Types.Struct}), do: true
  defp object_schema?(_schema), do: false

  defp normalize_validated(%Zoi.Types.Struct{fields: fields, meta: meta}, validated)
       when is_list(fields) and is_struct(validated) do
    value = Map.from_struct(validated)

    if Enum.any?(meta.effects, &match?({:transform, _}, &1)),
      do: value,
      else: Map.take(value, Enum.map(fields, &elem(&1, 0)))
  end

  defp normalize_validated(_schema, validated) when is_struct(validated),
    do: Map.from_struct(validated)

  defp normalize_validated(_schema, validated), do: validated

  defp format_zoi_error(%{path: path, message: message} = error) do
    %{path: path, message: message, code: Map.get(error, :code)}
  end

  defp error(message, details),
    do: {:error, Error.exception(message: message, details: details)}
end
