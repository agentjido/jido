defmodule Jido.Action.Validation do
  alias Jido.Joi
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
    if Joi.Schema.schema?(schema) do
      safely_validate(details, fn ->
        case Joi.parse(schema, data) do
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

  defp normalize_result(validated) when is_struct(validated),
    do: {:ok, Map.from_struct(validated)}

  defp normalize_result(validated), do: {:ok, validated}

  defp validation_error(errors, details) do
    {:error,
     Error.validation_error(
       Joi.prettify_errors(errors),
       Map.put(details, :errors, Enum.map(errors, &format_schema_error/1))
     )}
  end

  defp format_schema_error(%{path: path, message: message} = error) do
    %{
      path: path,
      message: message,
      code: Map.get(error, :code)
    }
  end
end
