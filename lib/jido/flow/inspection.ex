defmodule Jido.Flow.Inspection do
  @moduledoc false

  alias Jido.Flow.{Component, Value}
  alias Jido.Joi.Schema

  def requirements(ordered) do
    if Enum.any?(ordered, fn {_name, node} -> node.kind == :wait end), do: [:waits], else: []
  end

  def advisories(output, ordered) do
    producers =
      for {name, %{kind: :call, call: %{kind: :action, target: target}}} <- ordered,
          schema = closed_output(target),
          into: %{},
          do: {name, schema}

    if map_size(producers) == 0 do
      []
    else
      values = [output | Enum.flat_map(ordered, fn {_name, node} -> Component.values(node) end)]

      for value <- values,
          ref <- Value.result_references(value),
          missing_field?(producers[ref.component], ref.path),
          uniq: true do
        %{code: :unknown_result_field, component: ref.component, path: ref.path}
      end
    end
  end

  defp closed_output(target) do
    with true <- function_exported?(target, :__jido_codec_kind__, 0),
         true <- function_exported?(target, :output_schema, 0),
         :action <- target.__jido_codec_kind__(),
         schema = target.output_schema(),
         :error <- Schema.unknown_keys(schema),
         {:ok, fields} when is_list(fields) <- Schema.fields(schema) do
      schema
    else
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  defp missing_field?(schema, [key | rest]) do
    with :error <- Schema.unknown_keys(schema),
         {:ok, fields} when is_list(fields) <- Schema.fields(schema) do
      case Enum.find(fields, fn {field, _child} ->
             field == key or (is_atom(key) and field == Atom.to_string(key))
           end) do
        nil -> true
        {_field, child} -> missing_field?(child, rest)
      end
    else
      _ -> false
    end
  end

  defp missing_field?(_schema, []), do: false
end
