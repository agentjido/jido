defmodule Jido.Agent.Authoring.SourceMap do
  @moduledoc false

  alias Spark.Dsl.{Entity, Extension}

  def entity(entity, path) do
    properties =
      for field <- Map.keys(Map.from_struct(entity)),
          anno = Entity.property_anno(entity, field),
          not is_nil(anno),
          line(anno) > 1,
          into: %{},
          do: {path ++ [field], line(anno)}

    first = Enum.min(Map.values(properties), fn -> line(Entity.anno(entity)) end)
    Map.put(properties, path, first)
  end

  def collect(groups, locations, source \\ &entity/2) do
    for {field, entities} <- groups,
        {entity, index} <- Enum.with_index(entities),
        reduce: locations do
      locations -> Map.merge(locations, source.(entity, [field, index]))
    end
  end

  def section(dsl, path, fields, prefix) do
    locations =
      case Extension.get_section_anno(dsl, path) do
        nil -> %{}
        anno -> %{prefix => line(anno)}
      end

    for field <- fields,
        anno = Extension.get_opt_anno(dsl, path, field),
        not is_nil(anno),
        into: locations,
        do: {prefix ++ [field], line(anno)}
  end

  def lookup(locations, path, fallback) do
    case Map.fetch(locations, path) do
      {:ok, line} -> line
      :error when path == [] -> fallback
      :error -> lookup(locations, Enum.drop(path, -1), fallback)
    end
  end

  defp line(nil), do: 1
  defp line(anno), do: :erl_anno.line(anno)
end
