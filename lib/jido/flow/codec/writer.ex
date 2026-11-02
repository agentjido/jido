defmodule Jido.Flow.Codec.Writer do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias Jido.Flow.Error
  alias Jido.Flow.Codec.{Form, Limits, Value}

  @doc false
  @spec encode(Jido.Flow.t(), Registry.t()) :: {:ok, map()} | {:error, Exception.t()}
  def encode(flow, registry) do
    case do_encode(flow, registry) do
      {:error, %Registry.Error{} = error} ->
        message = String.replace(error.message, "authoring Registry", "Flow Registry")
        {:error, Error.validation_error(message, error.details)}

      result ->
        result
    end
  end

  defp do_encode(flow, registry) do
    with {:ok, schema} <- Registry.encode_reference(registry, :schema, flow.schema),
         {:ok, output_schema} <-
           Registry.encode_reference(registry, :schema, flow.output_schema),
         {:ok, forms} <- encode_forms(flow, registry),
         {:ok, output} <- Value.encode_expression(flow.output, registry, 0) do
      document = %{
        "type" => "jido.flow",
        "name" => flow.name,
        "description" => flow.description,
        "schema" => schema,
        "output_schema" => output_schema,
        "forms" => forms,
        "output" => output
      }

      with :ok <- Limits.check(document), do: {:ok, document}
    end
  end

  defp encode_forms(flow, registry) do
    flow.forms
    |> Enum.sort_by(&elem(&1, 0))
    |> sequence(fn {id, form} ->
      with {:ok, form} <- Form.encode(form, registry) do
        {:ok, [id, form, Map.get(flow.needs, id, [])]}
      end
    end)
  end

  defp sequence(values, encoder) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, encoded} ->
      case encoder.(value) do
        {:ok, value} -> {:cont, {:ok, [value | encoded]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end
end
