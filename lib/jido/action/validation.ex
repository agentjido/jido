defmodule Jido.Action.Validation do
  alias Jido.Joi
  @moduledoc false

  alias Jido.Action.{Error, Output}

  @doc false
  @spec schema(term(), term(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, Error.InvalidInputError.t()}
  def schema(schema, value, details, message \\ nil) do
    with {:ok, validated} <- parse(schema, value, details) do
      if is_map(validated) do
        {:ok, validated}
      else
        {:error,
         Error.validation_error(
           message || "#{details.context} validation must return a map",
           Map.put(details, :value, validated)
         )}
      end
    end
  end

  @doc false
  @spec output_schema(term(), term(), map()) ::
          {:ok, map() | Output.t()} | {:error, Error.InvalidInputError.t()}
  def output_schema(schema, %Output{kind: :preserve} = output, details) do
    with {:ok, output} <- Output.validate(output),
         {:ok, value} when is_map(value) <-
           parse_preserving_shape(schema, output.value, details) do
      {:ok, %{output | value: value}}
    else
      {:ok, value} ->
        {:error,
         Error.validation_error(
           "Action output validation must return a map",
           Map.put(details, :value, value)
         )}

      error ->
        error
    end
  end

  def output_schema(_schema, %Output{} = value, _details), do: Output.validate(value)

  def output_schema(schema, value, details),
    do: schema(schema, value, details, "Action output validation must return a map")

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
