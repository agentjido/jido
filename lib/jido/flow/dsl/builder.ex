defmodule Jido.Flow.DSL.Builder do
  @moduledoc false

  alias Jido.Flow
  alias Jido.Flow.Error
  alias Jido.Flow.DSL.{FormBuilder, Output, SourceMap, Step, ValueParser}

  @doc false
  @spec build(module(), map(), String.t()) ::
          {:ok, Flow.t(), Flow.source_map()} | {:error, Exception.t()}
  def build(module, config, file) do
    entities = Spark.Dsl.Extension.get_entities(module, [:flow])

    with {:ok, forms, output_entity} <- split_output(entities),
         {:ok, form_map, needs, sources} <- build_forms(forms, file),
         {:ok, output} <- build_output(output_entity) do
      sources = SourceMap.put_entity(sources, output_entity, :output, file)

      attrs =
        config
        |> Map.take([:name, :description, :schema, :output_schema])
        |> Map.merge(%{forms: form_map, needs: needs, output: output})

      case Flow.new(attrs) do
        {:ok, flow} -> {:ok, flow, sources}
        {:error, error} -> {:error, SourceMap.attach_error(error, sources)}
      end
    end
  end

  defp build_forms(forms, file) do
    forms
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, %{}, %{}, %{}}, fn {entity, index}, {:ok, forms, needs, sources} ->
      with {:ok, id, form, form_needs} <- build_form(entity),
           false <- Map.has_key?(forms, id) do
        needs = if form_needs == [], do: needs, else: Map.put(needs, id, form_needs)
        sources = SourceMap.put_entity(sources, entity, index, file)
        {:cont, {:ok, Map.put(forms, id, form), needs, sources}}
      else
        true ->
          error = Error.validation_error("duplicate Flow form name", %{form: entity.name})
          {:halt, {:error, SourceMap.attach_entity(error, entity)}}

        {:error, error} ->
          {:halt, {:error, SourceMap.attach_entity(error, entity)}}
      end
    end)
  end

  defp build_form(%Step{} = step) do
    with {:ok, %{params: params}} <- ValueParser.parse_fields(step, params: :value) do
      call = %{
        type: :call,
        action: step.action,
        params: params,
        metadata: step.meta,
        policy: step.policy,
        timeout_ms: step.timeout_ms,
        retry: step.retry,
        on_error: step.on_error
      }

      {:ok, step.name, call, step.needs}
    end
  end

  defp build_form(entity), do: FormBuilder.build(entity)

  defp build_output(nil), do: {:error, Error.validation_error("Flow output is required")}

  defp build_output(%Output{} = output) do
    with {:ok, %{value: value}} <- ValueParser.parse_fields(output, value: :value),
         do: {:ok, value}
  end

  defp split_output(entities) do
    case Enum.split_while(entities, &(not match?(%Output{}, &1))) do
      {forms, []} ->
        {:ok, forms, nil}

      {forms, [output]} ->
        {:ok, forms, output}

      {_forms, [output | _rest]} ->
        error = Error.validation_error("output must be the final Flow declaration")
        {:error, SourceMap.attach_entity(error, output)}
    end
  end
end
