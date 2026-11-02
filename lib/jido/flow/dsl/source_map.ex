defmodule Jido.Flow.DSL.SourceMap do
  @moduledoc false

  alias Jido.Flow.DSL.{Choice, Iterate, Output, Parallel}

  @doc false
  @spec put_entity(Jido.Flow.source_map(), struct(), non_neg_integer() | :output, String.t()) ::
          Jido.Flow.source_map()
  def put_entity(source_map, %Output{} = output, :output, file),
    do: put_source(source_map, [:output], output, file)

  def put_entity(source_map, entity, index, file) do
    Enum.reduce([index, entity.name], source_map, fn key, sources ->
      path = [:components, key]

      sources
      |> put_source(path, entity, file)
      |> put_nested_sources(path, entity, file)
    end)
  end

  @doc false
  @spec lookup(Jido.Flow.source_map(), map()) :: map() | nil
  def lookup(source_map, details) do
    paths =
      case details do
        %{path: [_ | _] = path} ->
          [path]

        %{component: component, field: :fallback} ->
          [[:components, component, :fallback], [:components, component]]

        %{component: component, field: field} when is_binary(field) ->
          [
            [:components, component, :options, field],
            [:components, component, :actions, field],
            [:components, component]
          ]

        %{component: component} ->
          [[:components, component]]

        _ ->
          []
      end

    Enum.find_value(paths, fn path ->
      Enum.find_value(length(path)..0//-1, &Map.get(source_map, Enum.take(path, &1)))
    end)
  end

  @doc false
  @spec attach_issue(Jido.Flow.Definition.issue(), Jido.Flow.source_map(), [map()]) ::
          Exception.t()
  def attach_issue(%{error: error, location: location}, source_map, components) do
    location =
      if location == [:components] do
        names = Map.get(error.details, :components, [])
        index = Enum.find_index(components, &(&1.name in names))
        if is_nil(index), do: location, else: [:components, index]
      else
        location
      end

    attach_error(error, source_map, location)
  end

  @doc false
  @spec attach_error(Exception.t(), Jido.Flow.source_map(), [term()] | nil) :: Exception.t()
  def attach_error(error, source_map, path \\ nil)

  def attach_error(%{details: details} = error, source_map, path) when is_map(details) do
    hints = if path, do: Map.put(details, :path, path), else: details
    attach_location(error, lookup(source_map, hints) || %{})
  end

  def attach_error(error, _source_map, _path), do: error

  @doc false
  @spec attach_entity(Exception.t(), struct()) :: Exception.t()
  def attach_entity(error, entity), do: attach_location(error, entity_source(entity))

  defp attach_location(%{details: details} = error, location) when is_map(details),
    do: %{error | details: Map.merge(location, details)}

  defp attach_location(error, _location), do: error

  defp put_nested_sources(source_map, path, %Choice{} = choice, file) do
    sources =
      choice.options
      |> Enum.with_index()
      |> Enum.reduce(source_map, fn {option, index}, sources ->
        Enum.reduce([index, option.name], sources, fn key, sources ->
          put_source(sources, path ++ [:options, key], option, file)
        end)
      end)

    put_source(sources, path ++ [:fallback], choice.fallback, file)
  end

  defp put_nested_sources(source_map, path, %Iterate{} = iterate, file) do
    source_map
    |> put_source(path ++ [:state], iterate.state, file)
    |> put_source(path ++ [:state, :update], iterate, file)
  end

  defp put_nested_sources(source_map, path, %Parallel{} = parallel, file) do
    parallel.actions
    |> Enum.with_index()
    |> Enum.reduce(source_map, fn {action, index}, sources ->
      Enum.reduce([index, action.name], sources, fn key, sources ->
        put_source(sources, path ++ [:actions, key], action, file)
      end)
    end)
  end

  defp put_nested_sources(source_map, _path, _entity, _file), do: source_map

  defp put_source(source_map, _path, nil, _file), do: source_map

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
