defmodule Jido.Flow.Codec.Reader do
  @moduledoc false

  alias Jido.Authoring.Registry
  alias Jido.Flow
  alias Jido.Flow.Error
  alias Jido.Flow.Codec.{Data, Form, Limits}

  @root_fields [
    "type",
    "name",
    "description",
    "schema",
    "output_schema",
    "forms",
    "output"
  ]

  @doc false
  @spec decode(term(), Registry.t()) :: {:ok, Flow.t()} | {:error, [Exception.t()]}
  def decode(%{} = document, registry) when not is_struct(document) do
    with :ok <- Limits.check(document),
         :ok <- envelope(document),
         :ok <- Data.exact_fields(document, @root_fields, []),
         {:ok, name} <- Data.required(document, "name", []),
         {:ok, description} <- Data.required(document, "description", []),
         {:ok, schema_record} <- Data.required(document, "schema", []),
         {:ok, schema} <- Data.decode_reference(schema_record, :schema, registry, ["schema"]),
         {:ok, output_schema_record} <- Data.required(document, "output_schema", []),
         {:ok, output_schema} <-
           Data.decode_reference(output_schema_record, :schema, registry, ["output_schema"]),
         {:ok, form_records} <- Data.required(document, "forms", []),
         {:ok, forms, needs} <- decode_forms(form_records, registry, ["forms"]),
         {:ok, output_record} <- Data.required(document, "output", []),
         {:ok, output} <- Data.decode_value(output_record, registry, ["output"]),
         {:ok, flow} <-
           Flow.new(%{
             name: name,
             description: description,
             schema: schema,
             output_schema: output_schema,
             forms: forms,
             needs: needs,
             output: output
           }) do
      {:ok, flow}
    else
      {:error, errors} when is_list(errors) -> {:error, errors}
      {:error, error} -> {:error, [error]}
    end
  end

  def decode(_document, _registry),
    do: failure("stored Flow document must be a map", [], :document)

  defp envelope(%{"type" => "jido.flow"}), do: :ok

  defp envelope(_document),
    do: failure("stored Flow document type must be jido.flow", ["type"], :type)

  defp decode_forms(records, registry, path) when is_list(records) do
    if List.improper?(records) do
      failure("stored Flow forms must be a proper list", path, :list)
    else
      records
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, %{}, %{}}, fn {record, index}, {:ok, forms, needs} ->
        case decode_form_record(record, registry, path ++ [index]) do
          {:ok, id, form, form_needs} ->
            if Map.has_key?(forms, id) do
              {:halt,
               failure(
                 "stored Flow contains a duplicate form",
                 path ++ [index, 0],
                 :duplicate_form
               )}
            else
              needs = if form_needs == [], do: needs, else: Map.put(needs, id, form_needs)
              {:cont, {:ok, Map.put(forms, id, form), needs}}
            end

          {:error, errors} ->
            {:halt, {:error, errors}}
        end
      end)
    end
  end

  defp decode_forms(_records, _registry, path),
    do: failure("stored Flow forms must be a list", path, :list)

  defp decode_form_record([id, record, needs], registry, path) when is_binary(id) do
    with {:ok, form} <- Form.decode(record, registry, path ++ [1]),
         {:ok, needs} <- decode_needs(needs, path ++ [2]) do
      {:ok, id, form, needs}
    end
  end

  defp decode_form_record(_record, _registry, path),
    do: failure("stored Flow form record must be [id, form, needs]", path, :form)

  defp decode_needs(needs, path) when is_list(needs) do
    cond do
      List.improper?(needs) -> failure("stored Flow needs must be a proper list", path, :list)
      Enum.all?(needs, &is_binary/1) -> {:ok, needs}
      true -> failure("stored Flow needs must contain strings", path, :needs)
    end
  end

  defp decode_needs(_needs, path),
    do: failure("stored Flow needs must be a list", path, :needs)

  defp failure(message, path, reason) do
    {:error, [Error.validation_error(message, %{path: path, reason: reason})]}
  end
end
