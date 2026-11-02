defmodule Jido.Flow.DSL.SourceMap do
  @moduledoc false

  alias Jido.Flow.DSL.Output

  @doc false
  @spec put_entity(map(), struct(), term(), String.t()) :: map()
  def put_entity(source_map, %Output{} = output, :output, file),
    do: put_source(source_map, [:output], output, file)

  def put_entity(source_map, entity, _index, file),
    do: put_source(source_map, [:forms, entity.name], entity, file)

  @doc false
  @spec lookup(map(), map()) :: map() | nil
  def lookup(source_map, details) do
    paths =
      case details do
        %{path: [_ | _] = path} -> [path]
        %{step: step} -> [[:forms, step]]
        _other -> []
      end

    Enum.find_value(paths, fn path ->
      Enum.find_value(length(path)..0//-1, &Map.get(source_map, Enum.take(path, &1)))
    end)
  end

  @doc false
  @spec attach_error(term(), map(), list() | nil) :: term()
  def attach_error(error, source_map, path \\ nil)

  def attach_error(%{details: details} = error, source_map, path) when is_map(details) do
    hints = if path, do: Map.put(details, :path, path), else: details
    attach_location(error, lookup(source_map, hints) || %{})
  end

  def attach_error(error, _source_map, _path), do: error

  @doc false
  @spec attach_entity(term(), struct()) :: term()
  def attach_entity(error, entity), do: attach_location(error, entity_source(entity))

  defp attach_location(%{details: details} = error, location) when is_map(details),
    do: %{error | details: Map.merge(location, details)}

  defp attach_location(error, _location), do: error

  defp put_source(source_map, path, entity, file),
    do: Map.put(source_map, path, Map.put_new(entity_source(entity), :file, file))

  defp entity_source(entity) do
    entity
    |> Spark.Dsl.Entity.anno()
    |> annotation_map()
    |> Map.merge(Map.get(entity, :__source__, %{}))
  end

  defp annotation_map(nil), do: %{}

  defp annotation_map(anno) do
    %{}
    |> maybe_put(:line, :erl_anno.line(anno))
    |> maybe_put(:column, :erl_anno.column(anno))
  end

  defp maybe_put(map, _key, :undefined), do: map
  defp maybe_put(map, _key, 0), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
