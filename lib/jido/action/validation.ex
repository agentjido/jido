defmodule Jido.Action.Validation do
  @moduledoc false

  alias Jido.Action.Error

  @doc false
  @spec parse(term(), term(), map()) ::
          {:ok, term()} | {:error, Error.InvalidInputError.t()}
  def parse(schema, data, details) when is_map(details),
    do: parse(schema, data, details, &normalize_result/1)

  @doc false
  @spec parse_preserving_shape(term(), term(), map()) ::
          {:ok, term()} | {:error, Error.InvalidInputError.t()}
  def parse_preserving_shape(schema, data, details) when is_map(details),
    do: parse(schema, data, details, &{:ok, &1})

  defp parse(schema, data, details, on_success) do
    if zoi_schema?(schema) do
      safely_validate(details, fn ->
        case Zoi.parse(schema, data) do
          {:ok, validated} -> on_success.(validated)
          {:error, errors} -> validation_error(errors, details)
        end
      end)
    else
      {:error, Error.validation_error("Unsupported schema type", details)}
    end
  end

  defp safely_validate(details, validate) do
    validate.()
  rescue
    exception ->
      {:error,
       Error.validation_error(
         "schema validation failed",
         Map.merge(details, %{
           exception: exception.__struct__,
           reason: Exception.message(exception)
         })
       )}
  catch
    kind, reason ->
      {:error,
       Error.validation_error(
         "schema validation failed",
         Map.merge(details, %{failure_kind: kind, reason: inspect(reason)})
       )}
  end

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

  defp resolve_lazy(%Zoi.Types.Lazy{fun: {module, function, args}}),
    do: apply(module, function, args)

  defp resolve_lazy(%Zoi.Types.Lazy{fun: fun}), do: fun.()

  defp normalize_result(validated) when is_struct(validated),
    do: {:ok, Map.from_struct(validated)}

  defp normalize_result(validated), do: {:ok, validated}

  defp validation_error(errors, details) do
    {:error,
     Error.validation_error(
       Zoi.prettify_errors(errors),
       Map.put(details, :errors, Enum.map(errors, &format_zoi_error/1))
     )}
  end

  defp format_zoi_error(%{path: path, message: message} = error) do
    %{
      path: path,
      message: message,
      code: Map.get(error, :code)
    }
  end
end
